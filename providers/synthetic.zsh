# providers/synthetic.zsh - Synthetic API provider
# Generic OpenAI-compatible API provider for custom/local endpoints
# Configure with ZSH_AI_CMD_SYNTHETIC_BASE_URL and ZSH_AI_CMD_SYNTHETIC_MODEL

typeset -g ZSH_AI_CMD_SYNTHETIC_MODEL=${ZSH_AI_CMD_SYNTHETIC_MODEL:-'hf:moonshotai/Kimi-K2.5'}
typeset -g ZSH_AI_CMD_SYNTHETIC_BASE_URL=${ZSH_AI_CMD_SYNTHETIC_BASE_URL:-'https://api.synth.sh/v1/chat/completions'}

_zsh_ai_cmd_synthetic_call() {
  local input=$1
  local prompt=$2

  local payload
  payload=$(command jq -nc \
    --arg model "$ZSH_AI_CMD_SYNTHETIC_MODEL" \
    --arg system "$prompt" \
    --arg content "$input" \
    '{
      model: $model,
      max_completion_tokens: 256,
      messages: [
        {role: "system", content: $system},
        {role: "user", content: $content}
      ],
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "shell_command",
          schema: {
            type: "object",
            properties: {
              command: {type: "string", description: "The shell command"}
            },
            required: ["command"],
            additionalProperties: false
          },
          strict: true
        }
      }
    }')

  local response
  response=$(command curl -sS --max-time 30 "$ZSH_AI_CMD_SYNTHETIC_BASE_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $SYNTHETIC_API_KEY" \
    -d "$payload" 2>/dev/null)

  # Debug log
  if [[ $ZSH_AI_CMD_DEBUG == true ]]; then
    {
      print -- "=== $(date '+%Y-%m-%d %H:%M:%S') [synthetic] ==="
      print -- "--- REQUEST ---"
      command jq . <<< "$payload"
      print -- "--- RESPONSE ---"
      command jq . <<< "$response"
      print ""
    } >>$ZSH_AI_CMD_LOG
  fi

  # Check for API error
  local error_msg
  error_msg=$(print -r -- "$response" | command jq -re '.error.message // empty' 2>/dev/null)
  if [[ -n $error_msg ]]; then
    print -u2 "zsh-ai-cmd [synthetic]: $error_msg"
    return 1
  fi

  # Extract command from response
  print -r -- "$response" | command jq -re '.choices[0].message.content | fromjson | .command // empty' 2>/dev/null
}

_zsh_ai_cmd_synthetic_key_error() {
  print -u2 ""
  print -u2 "zsh-ai-cmd: SYNTHETIC_API_KEY not found"
  print -u2 ""
  print -u2 "Set it via environment variable:"
  print -u2 "  export SYNTHETIC_API_KEY='...'"
  print -u2 ""
  print -u2 "Or store in macOS Keychain:"
  print -u2 "  security add-generic-password -s 'synthetic-api-key' -a '\$USER' -w '...'"
  print -u2 ""
  print -u2 "Current configuration:"
  print -u2 "  Model: $ZSH_AI_CMD_SYNTHETIC_MODEL"
  print -u2 "  Base URL: $ZSH_AI_CMD_SYNTHETIC_BASE_URL"
}
