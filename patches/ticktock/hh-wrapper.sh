#!/bin/bash
# Hermes CLI wrapper with ticktock time awareness.
# Usage: hh [hermes args...]
# Replaces: hermes → hh

TICKTOCK=$(python3 ~/.local/bin/hermes_ticktock.py cli-session 2>/dev/null)
if [ -n "$TICKTOCK" ]; then
    export HERMES_EPHEMERAL_SYSTEM_PROMPT="$TICKTOCK"
fi

exec hermes "$@"
