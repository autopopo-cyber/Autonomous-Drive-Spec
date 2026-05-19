#!/bin/bash
# 俊秀部署 — 一键config配置
# 前提: .env已填好, SOUL.md已复制到 ~/.hermes/
set -e

echo "🔧 俊秀配置中..."

# DeepSeek
hermes config set model.provider      deepseek
hermes config set model.default       deepseek-v4-pro
hermes config set model.base_url      https://api.deepseek.com
DS_KEY=$(grep DEEPSEEK_API_KEY ~/.hermes/.env | cut -d= -f2)
hermes config set model.main.api_key  "$DS_KEY"

# 人格
cp SOUL.md ~/.hermes/SOUL.md
mkdir -p ~/.hermes/memories
cp MEMORY.md ~/.hermes/memories/MEMORY.md
cp USER.md ~/.hermes/memories/USER.md
hermes config set prefill_messages_file ~/.hermes/SOUL.md
hermes config set display.personality  custom
echo "SOUL + MEMORY + USER 已部署"

# 压缩
hermes config set compression.provider deepseek
hermes config set compression.model   deepseek-v4-flash

# 安全
hermes config set approvals.mode       off

# 飞书
hermes config set platforms.feishu.enabled true

# 重启
echo "🔄 重启gateway..."
pkill -f "gateway run" 2>/dev/null || true
sleep 2
nohup hermes gateway run --replace > /tmp/hermes-gateway.log 2>&1 &
sleep 5

# 验证
if ps aux | grep "gateway run" | grep -v grep | grep -q hermes; then
    echo "✅ gateway已启动"
else
    echo "❌ gateway未启动，查看日志: tail /tmp/hermes-gateway.log"
    exit 1
fi

echo "✅ 配置完成。运行 self-check.sh 验证。"
