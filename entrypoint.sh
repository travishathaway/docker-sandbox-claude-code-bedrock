#!/bin/bash
set -e

# sbx (Docker Sandboxes) mounts host directories at their original host path
# inside the sandbox VM — e.g. /Users/alice/.aws — rather than at the
# container user's $HOME (/home/agent). This means the AWS CLI and Claude Code
# cannot find credentials or config in the expected locations.
#
# This entrypoint:
#   1. Detects host-mounted ~/.aws and ~/.claude and symlinks them into $HOME
#   2. Reads the env block from ~/.claude/settings.json and writes those
#      variables into /etc/sandbox-persistent.sh (pointed to by CLAUDE_ENV_FILE),
#      so that CLAUDE_CODE_USE_BEDROCK and AWS_PROFILE are in the environment
#      before Claude Code's auth check runs.

AGENT_HOME="/home/agent"
AWS_MOUNT=""
CLAUDE_MOUNT=""

# ---------------------------------------------------------------------------
# Detect mounts
# Strategy 1: virtiofs entries in /proc/mounts (sbx sandbox environment)
# Strategy 2: filesystem scan (plain Docker volume mounts / CI)
# ---------------------------------------------------------------------------
if grep -q virtiofs /proc/mounts 2>/dev/null; then
    while read -r _ mountpoint _ _; do
        case "$mountpoint" in
            */.aws)    AWS_MOUNT="$mountpoint" ;;
            */.claude) CLAUDE_MOUNT="$mountpoint" ;;
        esac
    done < <(grep virtiofs /proc/mounts)
fi

if [[ -z "$AWS_MOUNT" ]]; then
    AWS_MOUNT=$(find / -maxdepth 4 -mindepth 3 -name ".aws" -type d \
        ! -path "${AGENT_HOME}/*" 2>/dev/null | head -1)
fi

if [[ -z "$CLAUDE_MOUNT" ]]; then
    CLAUDE_MOUNT=$(find / -maxdepth 4 -mindepth 3 -name ".claude" -type d \
        ! -path "${AGENT_HOME}/*" 2>/dev/null | head -1)
fi

# ---------------------------------------------------------------------------
# Symlink ~/.aws and ~/.claude into $HOME
# ---------------------------------------------------------------------------
if [[ -n "$AWS_MOUNT" ]]; then
    rm -rf "${AGENT_HOME}/.aws"
    ln -s "$AWS_MOUNT" "${AGENT_HOME}/.aws"
fi

if [[ -n "$CLAUDE_MOUNT" ]]; then
    rm -rf "${AGENT_HOME}/.claude"
    ln -s "$CLAUDE_MOUNT" "${AGENT_HOME}/.claude"
fi

# ---------------------------------------------------------------------------
# Inject env vars from ~/.claude/settings.json into /etc/sandbox-persistent.sh
#
# Claude Code reads CLAUDE_ENV_FILE (=/etc/sandbox-persistent.sh) before its
# auth check, but only processes the settings.json env block after startup.
# Writing the vars here ensures CLAUDE_CODE_USE_BEDROCK=1 and AWS_PROFILE are
# present in the environment when the auth check runs.
# ---------------------------------------------------------------------------
SETTINGS="${AGENT_HOME}/.claude/settings.json"
ENV_FILE="${CLAUDE_ENV_FILE:-/etc/sandbox-persistent.sh}"

if [[ -f "$SETTINGS" ]]; then
    node -e "
        const s = JSON.parse(require('fs').readFileSync('$SETTINGS', 'utf8'));
        const env = s.env || {};
        const lines = Object.entries(env).map(([k,v]) => \`export \${k}=\${JSON.stringify(String(v))}\`);
        if (lines.length) process.stdout.write(lines.join('\n') + '\n');
    " >> "$ENV_FILE" 2>/dev/null || true
fi

exec "$@"
