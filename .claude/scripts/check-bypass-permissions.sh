#!/usr/bin/env sh
# Report whether a Claude Code session was launched with --dangerously-skip-permissions.
#
# The EXIT CODE is the answer; stdout is always empty (output filters/proxies such as
# RTK token compression can rewrite stdout, so it is never used to carry the result):
#
#   0 -> bypass permissions is OFF
#   1 -> bypass permissions is ON
#
# Usage: check-bypass-permissions.sh [PID]      (PID defaults to $CLAUDE_PID)
#
# Why the PID matters: this inspects the command line of exactly ONE process — the
# claude process of the *current* session, published by the harness as $CLAUDE_PID.
# Scanning the whole process table instead (the old `ps aux | grep` approach) is wrong
# twice over: on Windows it can never see the native claude process, and everywhere it
# matches unrelated processes whose command line merely quotes the flag, such as a shell
# echoing a prompt that mentions it.

set -u

pid="${1:-${CLAUDE_PID:-}}"

# No PID to inspect: assume OFF. That is the conservative answer — the caller then
# prompts for permissions it may not have needed, rather than silently skipping a
# prompt it did need.
[ -n "$pid" ] || exit 0

case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*|*_NT*) os=windows ;;
    *)                          os=posix   ;;
esac

cmdline=""

if [ "$os" = posix ]; then
    # Linux / WSL: /proc is authoritative and needs no external command.
    if [ -r "/proc/$pid/cmdline" ]; then
        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    fi
    # macOS and any POSIX without /proc: both BSD and GNU ps support -o args=.
    if [ -z "$cmdline" ]; then
        cmdline=$(ps -p "$pid" -o args= 2>/dev/null)
    fi
else
    # Git Bash / MSYS: `ps` lists only MSYS processes and never sees the native
    # claude.exe, and MSYS PIDs are a different namespace from the Windows PID in
    # $CLAUDE_PID — so /proc and ps are skipped entirely here. Ask Windows instead.
    if command -v powershell.exe >/dev/null 2>&1; then
        cmdline=$(powershell.exe -NoProfile -NonInteractive -Command \
            "(Get-CimInstance Win32_Process -Filter \"ProcessId=$pid\").CommandLine" 2>/dev/null)
    fi
fi

printf '%s' "$cmdline" | grep -q -- '--dangerously-skip-permissions' && exit 1
exit 0
