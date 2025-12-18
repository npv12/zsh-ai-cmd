# zsh-ai-cmd

Natural language to shell commands with ghost text preview.

![Demo](assets/preview.gif)

## Install

Requires `curl`, `jq`, and an [Anthropic API key](https://console.anthropic.com/).

```sh
# Clone
git clone https://github.com/kylesnowschwartz/zsh-ai-cmd ~/.zsh-ai-cmd

# Add to .zshrc
source ~/.zsh-ai-cmd/zsh-ai-cmd.plugin.zsh

# Set API key (pick one)
export ANTHROPIC_API_KEY='sk-ant-...'
# or macOS Keychain
security add-generic-password -s 'anthropic-api-key' -a "$USER" -w 'sk-ant-...'
```

## Usage

1. Type a natural language description
2. Press `Ctrl+Z` to request a suggestion
3. Ghost text appears showing the command: `find large files → command find . -size +100M`
4. Press `Tab` to accept, or keep typing to dismiss

If the suggestion extends your input (you started typing a command), ghost text shows the completion inline. Otherwise, it shows the full suggestion with an arrow.

## Configuration

```sh
ZSH_AI_CMD_KEY='^z'                          # Trigger key (default: Ctrl+Z)
ZSH_AI_CMD_MODEL='claude-haiku-4-5-20251001' # Model
ZSH_AI_CMD_DEBUG=false                       # Enable debug logging
ZSH_AI_CMD_LOG=/tmp/zsh-ai-cmd.log           # Debug log path
```
