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

## Integration (Hermes 0.12+)

The patch to `session.py` is already in Hermes core as of the latest version.
No manual patching needed after `hermes update`.

If needed manually, insert before `lines = [...]` in `build_session_context_prompt()`:

```python
import subprocess as _sp
_sid = context.session_id or "default"
_ticktock = _sp.run(["python3", "/path/to/ticktock.py", _sid],
    capture_output=True, text=True, timeout=2)
_tt_line = _ticktock.stdout.strip()
# prepend _tt_line to lines list
```
