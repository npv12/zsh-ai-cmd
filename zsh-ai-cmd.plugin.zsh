#!/usr/bin/env zsh
# zsh-ai-cmd.plugin.zsh - HUD-style AI shell suggestions (ghost text)
# External deps: curl, jq, security (macOS Keychain)

zmodload zsh/zpty 2>/dev/null || { print -u2 "zsh-ai-cmd: requires zsh/zpty"; return 1; }

# ============================================================================
# Configuration
# ============================================================================
typeset -g ZSH_AI_CMD_DEBUG=${ZSH_AI_CMD_DEBUG:-false}
typeset -g ZSH_AI_CMD_MODEL=${ZSH_AI_CMD_MODEL:-'claude-haiku-4-5-20251001'}
typeset -g ZSH_AI_CMD_MIN_CHARS=${ZSH_AI_CMD_MIN_CHARS:-5}

# ============================================================================
# Internal State
# ============================================================================
typeset -g _ZSH_AI_CMD_SUGGESTION=""
typeset -g _ZSH_AI_CMD_LAST_BUFFER=""
typeset -g _ZSH_AI_CMD_PTY="zsh_ai_cmd_pty"

# Cache OS at load time
typeset -g _ZSH_AI_CMD_OS
if [[ $OSTYPE == darwin* ]]; then
  _ZSH_AI_CMD_OS="macOS $(sw_vers -productVersion 2>/dev/null || print 'unknown')"
else
  _ZSH_AI_CMD_OS="Linux"
fi

# ============================================================================
# System Prompt
# ============================================================================
typeset -g _ZSH_AI_CMD_PROMPT='Complete the user intent as a shell command.

RULES:
- Output EXACTLY ONE command, nothing else
- Complete partial intents speculatively
- If input looks like a command already, output it unchanged
- If input is natural language, translate to shell
- Prefix standard tools with `command` to bypass aliases

<examples>
User: list files
command ls -la

User: find py
command find . -name "*.py"

User: git st
git status

User: show disk
command df -h

User: kill port 3000
command lsof -ti:3000 | xargs kill -9

User: grep TODO
command grep -r "TODO" .
</examples>'

typeset -g _ZSH_AI_CMD_CONTEXT='<context>
OS: $_ZSH_AI_CMD_OS
Shell: ${SHELL:t}
PWD: $PWD
</context>'

# ============================================================================
# Ghost Text Rendering
# ============================================================================

_zsh_ai_cmd_show_ghost() {
  local suggestion=$1
  [[ $ZSH_AI_CMD_DEBUG == true ]] && print -- "show_ghost: suggestion='$suggestion' BUFFER='$BUFFER'" >> /tmp/zsh-ai-cmd.log
  if [[ -n $suggestion && $suggestion != $BUFFER ]]; then
    if [[ $suggestion == ${BUFFER}* ]]; then
      POSTDISPLAY="${suggestion#$BUFFER}"
    else
      POSTDISPLAY=" → $suggestion"
    fi
    [[ $ZSH_AI_CMD_DEBUG == true ]] && print -- "show_ghost: POSTDISPLAY='$POSTDISPLAY'" >> /tmp/zsh-ai-cmd.log
  else
    POSTDISPLAY=""
  fi
}

_zsh_ai_cmd_clear_ghost() {
  POSTDISPLAY=""
  _ZSH_AI_CMD_SUGGESTION=""
}

# ============================================================================
# Async API using zpty
# ============================================================================

_zsh_ai_cmd_cleanup_pty() {
  zpty -d "$_ZSH_AI_CMD_PTY" 2>/dev/null
}

# Worker function that runs in the pty
_zsh_ai_cmd_worker() {
  local input=$1 api_key=$2 model=$3 prompt=$4

  local schema='{
    "type": "object",
    "properties": {
      "command": {"type": "string", "description": "The shell command"}
    },
    "required": ["command"],
    "additionalProperties": false
  }'

  local payload
  payload=$(command jq -nc \
    --arg model "$model" \
    --arg system "$prompt" \
    --arg content "$input" \
    --argjson schema "$schema" \
    '{
      model: $model,
      max_tokens: 128,
      system: $system,
      messages: [{role: "user", content: $content}],
      output_format: {type: "json_schema", schema: $schema}
    }')

  local response
  response=$(command curl -sS --max-time 10 "https://api.anthropic.com/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $api_key" \
    -H "anthropic-version: 2023-06-01" \
    -H "anthropic-beta: structured-outputs-2025-11-13" \
    -d "$payload" 2>/dev/null)

  local suggestion
  suggestion=$(print -r -- "$response" | command jq -re '.content[0].text | fromjson | .command // empty' 2>/dev/null)

  # Output just the suggestion (will be read by callback)
  print -r -- "$suggestion"
}

# Callback when pty has output (runs in ZLE context)
_zsh_ai_cmd_pty_callback() {
  local fd=$1
  local err=$2

  # Handle errors/hangup
  if [[ -n $err ]]; then
    [[ $ZSH_AI_CMD_DEBUG == true ]] && print -- "pty_callback: error '$err'" >> /tmp/zsh-ai-cmd.log
    zle -F $fd
    _zsh_ai_cmd_cleanup_pty
    return
  fi

  # Read from pty with timeout
  local suggestion=""
  zpty -r "$_ZSH_AI_CMD_PTY" suggestion '*'$'\n' 2>/dev/null

  # Clean up trailing whitespace/newlines
  suggestion="${suggestion%%$'\n'}"
  suggestion="${suggestion%%$'\r'}"
  suggestion="${suggestion## }"  # trim leading space

  [[ $ZSH_AI_CMD_DEBUG == true ]] && print -- "pty_callback: got '$suggestion'" >> /tmp/zsh-ai-cmd.log

  if [[ -n $suggestion ]]; then
    _ZSH_AI_CMD_SUGGESTION=$suggestion

    # Only show if buffer hasn't changed
    if [[ $BUFFER == $_ZSH_AI_CMD_LAST_BUFFER ]]; then
      _zsh_ai_cmd_show_ghost "$suggestion"
      zle -R
    fi

    # Cleanup after getting result
    zle -F $fd
    _zsh_ai_cmd_cleanup_pty
  fi
}

# Fire async request
_zsh_ai_cmd_request_async() {
  local input=$1

  [[ $ZSH_AI_CMD_DEBUG == true ]] && print -- "request_async: '$input'" >> /tmp/zsh-ai-cmd.log

  _zsh_ai_cmd_get_key || return 1
  _zsh_ai_cmd_cleanup_pty

  local context="${(e)_ZSH_AI_CMD_CONTEXT}"
  local prompt="${_ZSH_AI_CMD_PROMPT}"$'\n'"${context}"

  # Start worker in pty - zpty stores fd in $REPLY (zsh 5.0.8+)
  zpty "$_ZSH_AI_CMD_PTY" "_zsh_ai_cmd_worker ${(q)input} ${(q)ANTHROPIC_API_KEY} ${(q)ZSH_AI_CMD_MODEL} ${(q)prompt}"
  local pty_fd=$REPLY

  [[ $ZSH_AI_CMD_DEBUG == true ]] && print -- "request_async: REPLY='$REPLY' pty_fd='$pty_fd'" >> /tmp/zsh-ai-cmd.log

  if [[ -n $pty_fd && $pty_fd =~ ^[0-9]+$ ]]; then
    zle -F $pty_fd _zsh_ai_cmd_pty_callback
    _ZSH_AI_CMD_LAST_BUFFER=$input
  else
    [[ $ZSH_AI_CMD_DEBUG == true ]] && print -- "request_async: failed to get pty fd" >> /tmp/zsh-ai-cmd.log
  fi
}

# ============================================================================
# Input Handling
# ============================================================================

_zsh_ai_cmd_on_buffer_change() {
  if [[ -n $POSTDISPLAY ]]; then
    if [[ -n $_ZSH_AI_CMD_SUGGESTION && $_ZSH_AI_CMD_SUGGESTION == ${BUFFER}* ]]; then
      _zsh_ai_cmd_show_ghost "$_ZSH_AI_CMD_SUGGESTION"
    else
      _zsh_ai_cmd_clear_ghost
    fi
  fi

  (( ${#BUFFER} < ZSH_AI_CMD_MIN_CHARS )) && return
  [[ $BUFFER == $_ZSH_AI_CMD_LAST_BUFFER ]] && return

  if [[ $BUFFER =~ ^(cd|ls|git|cat|rm|mv|cp|mkdir|echo|grep|find|sed|awk|curl|wget|npm|yarn|docker|kubectl|python|ruby|node)[[:space:]] ]]; then
    return
  fi

  [[ $ZSH_AI_CMD_DEBUG == true ]] && print -- "on_buffer_change: requesting '$BUFFER'" >> /tmp/zsh-ai-cmd.log
  _zsh_ai_cmd_request_async "$BUFFER"
}

_zsh_ai_cmd_accept() {
  if [[ -n $_ZSH_AI_CMD_SUGGESTION ]]; then
    BUFFER=$_ZSH_AI_CMD_SUGGESTION
    CURSOR=$#BUFFER
    _zsh_ai_cmd_clear_ghost
  else
    zle expand-or-complete
  fi
}

# ============================================================================
# Widget Registration
# ============================================================================

_zsh_ai_cmd_line_init() {
  _zsh_ai_cmd_clear_ghost
}

_zsh_ai_cmd_line_finish() {
  _zsh_ai_cmd_cleanup_pty
  _zsh_ai_cmd_clear_ghost
}

_zsh_ai_cmd_self_insert() {
  zle .self-insert
  [[ $ZSH_AI_CMD_DEBUG == true ]] && print -- "self-insert: '$BUFFER' len=${#BUFFER}" >> /tmp/zsh-ai-cmd.log
  _zsh_ai_cmd_on_buffer_change
}

_zsh_ai_cmd_backward_delete_char() {
  zle .backward-delete-char
  _zsh_ai_cmd_on_buffer_change
}

zle -N zle-line-init _zsh_ai_cmd_line_init
zle -N zle-line-finish _zsh_ai_cmd_line_finish
zle -N self-insert _zsh_ai_cmd_self_insert
zle -N backward-delete-char _zsh_ai_cmd_backward_delete_char
zle -N _zsh_ai_cmd_accept

bindkey '^I' _zsh_ai_cmd_accept

# ============================================================================
# API Key Management
# ============================================================================
_zsh_ai_cmd_get_key() {
  [[ -n $ANTHROPIC_API_KEY ]] && return 0
  ANTHROPIC_API_KEY=$(security find-generic-password \
    -s "anthropic-api-key" -a "$USER" -w 2>/dev/null) || return 1
}
