# Changelog

All notable changes to zsh-ai-cmd are documented in this file.

## [v0.1.0] - 2026-01-26

### Added
- **Custom API Key Command Support** (`ZSH_AI_CMD_API_KEY_COMMAND`)
  - Retrieve API keys via custom commands (e.g., `secret-tool`, `pass`, 1Password CLI, AWS Secrets Manager)
  - Dynamic `${provider}` expansion in command string
  - Case normalization for provider handling (ANTHROPIC, Anthropic, anthropic all work)
  - Automatic output sanitization (strips control chars and escape sequences)
  - Secure debug logging (never logs actual key values)
  - Silent fallback to Keychain if command fails
  - Opt-in feature (empty default, no behavior change without config)

### API Key Retrieval Sequence
Keys are now retrieved in this order:
1. Environment variables (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.)
2. Custom command (`ZSH_AI_CMD_API_KEY_COMMAND` with `${provider}` expansion) — if configured
3. macOS Keychain (`ZSH_AI_CMD_KEYCHAIN_NAME`)

### Examples
```sh
# Linux with GNOME Keyring
export ZSH_AI_CMD_API_KEY_COMMAND='secret-tool lookup service ${provider}'

# pass password manager
export ZSH_AI_CMD_API_KEY_COMMAND='pass show ${provider}-api-key'

# 1Password CLI
export ZSH_AI_CMD_API_KEY_COMMAND='op read op://Private/${provider}-api-key'

# AWS Secrets Manager
export ZSH_AI_CMD_API_KEY_COMMAND='aws secretsmanager get-secret-value --secret-id ${provider}-api-key --query SecretString --output text'
```

### Testing
- Added 21 comprehensive feature tests in `test-api-key-command.sh`
- All 19 existing API validation tests pass
- Full backwards compatibility verified
- Case normalization tests included

### Documentation
- Updated README.md with new "Custom API Key Retrieval" section
- Updated CLAUDE.md with API Key Retrieval details
- Added this CHANGELOG.md
- Created VERSION file for runtime version checking

---

## Release Notes

**Initial Release**: Implements custom command-based API key retrieval as requested in #11. Design emphasizes security, flexibility, and backwards compatibility.
