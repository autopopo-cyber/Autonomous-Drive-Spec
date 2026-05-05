# TickTock — LLM Time Awareness

Inject real-time clock + turn delta into Hermes system prompt for temporal awareness.

## How It Works

Gateway's `session.py::build_session_context_prompt()` calls `ticktock.py <session_id>` each turn.
The script maintains per-session timestamp files at `/tmp/hermes_last_turn_ts_<session_id>`.

## Effect

Every turn starts with:
```
[当前时间: 2026-05-05 20:54:51 CST | 距上回合: 327s]
```

LLM can feel conversation rhythm — short gap means user is typing, long gap means user was thinking/away.

## Integration

### Gateway Sessions (WeChat, Telegram, Discord, etc.)

Patch `session.py::build_session_context_prompt()` — inject ticktock into system prompt at turn start.
See `patches/ticktock-patch.md` for the exact diff.

### CLI Sessions

Patch `cli.py` in `HermesCLI.__init__()` — inject ticktock into `self.system_prompt` before it's passed to AIAgent.
Or use the `hh` wrapper script for a non-invasive approach.
