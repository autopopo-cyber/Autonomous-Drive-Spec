"""Write timestamp and session_active flag on agent lifecycle events."""
from pathlib import Path
from datetime import datetime

TIMESTAMP_FILE = Path("/tmp/junxiu_last_msg.txt")
ACTIVE_FILE = Path("/tmp/junxiu_session_active.txt")


def handle(event_type: str, context: dict):
    ts = str(int(datetime.now().timestamp()))
    TIMESTAMP_FILE.write_text(ts)

    if event_type == "agent:start":
        ACTIVE_FILE.write_text("1")
    elif event_type == "agent:end":
        ACTIVE_FILE.write_text("0")
