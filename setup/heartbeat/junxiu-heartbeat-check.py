#!/usr/bin/env python3
"""Heartbeat check — only output if last message was >15 min ago."""
import sys
from pathlib import Path
from datetime import datetime

TIMESTAMP_FILE = Path("/tmp/junxiu_last_msg.txt")
THRESHOLD = 15 * 60  # 15 minutes

if not TIMESTAMP_FILE.exists():
    # No messages yet — don't send
    sys.exit(0)

try:
    last_ts = int(TIMESTAMP_FILE.read_text().strip())
    elapsed = int(datetime.now().timestamp()) - last_ts
    if elapsed > THRESHOLD:
        print("我暂时不在，小俊秀自己看看memtree有什么可以推动的，或者休息会儿。")
    # else: silent — no output = no delivery
except (ValueError, OSError):
    pass
