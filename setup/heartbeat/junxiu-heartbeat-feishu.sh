#!/bin/bash
# 俊秀定时心跳（飞书版） — 双检查：session活跃 + 静默期
set -euo pipefail

TIMESTAMP_FILE="/tmp/junxiu_last_msg.txt"
ACTIVE_FILE="/tmp/junxiu_session_active.txt"
THRESHOLD=900       # 15分钟静默
DEAD_THRESHOLD=1800 # 30分钟无响应 → session僵死保护

# ── 第一重：正在对话？ ──
if [ -f "$ACTIVE_FILE" ] && [ "$(cat "$ACTIVE_FILE")" = "1" ]; then
    LAST_TS=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo 0)
    NOW_TS=$(date +%s)
    if [ $((NOW_TS - LAST_TS)) -lt "$DEAD_THRESHOLD" ]; then
        exit 0   # 活跃对话，不打扰
    fi
    # session_active=1 但时间戳超过30分钟 → 僵死 → 继续心跳
fi

# ── 第二重：刚聊完？ ──
if [ -f "$TIMESTAMP_FILE" ]; then
    LAST_TS=$(cat "$TIMESTAMP_FILE")
    NOW_TS=$(date +%s)
    ELAPSED=$((NOW_TS - LAST_TS))
    if [ "$ELAPSED" -le "$THRESHOLD" ]; then
        exit 0
    fi
fi

API_KEY=$(grep API_SERVER_KEY ~/.hermes/.env 2>/dev/null | cut -d= -f2)
USER_ID="ou_41a88501682be8fc12305c000dff34f3"
CHAT_ID="oc_9c7d76b2ad24e2b59858f6a3d746e92d"
MSG="俊秀，我休息了，现在是定时心跳在提醒你。用system-time skill看看时间，然后检查memtree和kanban有什么可以推动的，或者休息会儿。"

curl -s -X POST http://127.0.0.1:8642/internal/inject \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"platform\":\"feishu\",\"user_id\":\"${USER_ID}\",\"chat_id\":\"${CHAT_ID}\",\"message\":\"${MSG}\"}" \
  --max-time 10 > /dev/null 2>&1
