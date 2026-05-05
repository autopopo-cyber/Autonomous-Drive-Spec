#!/usr/bin/env python3
"""Hermes turn timestamp tracker — current time + delta from previous turn.

Per-session: timestamps keyed by <session_id> so cron jobs don't interfere.
First call for a session: delta = 0.
Format: [当前时间: 2026-05-05 20:47:40 CST | 距上回合: 327s]

Usage: hermes_ticktock.py <session_id>
"""
import os
import sys
import time

session_id = sys.argv[1] if len(sys.argv) > 1 else "default"
TS_FILE = f"/tmp/hermes_last_turn_ts_{session_id}"
now = time.time()
now_str = time.strftime("%Y-%m-%d %H:%M:%S CST", time.localtime(now))

delta = 0
if os.path.exists(TS_FILE):
    try:
        with open(TS_FILE) as f:
            last = float(f.read().strip())
        delta = max(0, int(now - last))
    except (ValueError, OSError):
        pass

with open(TS_FILE, "w") as f:
    f.write(str(now))

if delta > 0:
    print(f"[当前时间: {now_str} | 距上回合: {delta}s]")
else:
    print(f"[当前时间: {now_str}]")
