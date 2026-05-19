#!/bin/bash
# ============================================
# 俊秀自检脚本 v1.1
# 用法: bash self-check.sh [机器编号]
# 输出: 全部PASS→exit 0, 任何FAIL→exit 1
# ============================================
set -e

# PATH：hermes装在 ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

MACHINE_ID="${1:-unknown}"
PASS=0
FAIL=0
REPORT=""

check() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" > /dev/null 2>&1; then
        echo "  ✅ $name"
        PASS=$((PASS + 1))
    else
        echo "  ❌ $name"
        FAIL=$((FAIL + 1))
        REPORT="$REPORT\n  FAIL: $name"
    fi
}

echo "╔══════════════════════════════════════╗"
echo "║   俊秀自检 — $MACHINE_ID"
echo "╚══════════════════════════════════════╝"
echo ""

# ── 1. 基础 ──
echo "── 基础 ──"
check "hermes已安装"            'which hermes'
check "SOUL.md存在"             'test -f ~/.hermes/SOUL.md'
check "SOUL.md非空(>1KB)"      'test $(wc -c < ~/.hermes/SOUL.md) -gt 1000'
check "MEMORY.md存在"          'test -f ~/.hermes/memories/MEMORY.md'
check "USER.md存在"            'test -f ~/.hermes/memories/USER.md'

# ── 2. 密钥 ──
echo "── 密钥 ──"
check ".env存在"               'test -f ~/.hermes/.env'
check "DEEPSEEK_API_KEY已设"   'grep -q "DEEPSEEK_API_KEY=sk-" ~/.hermes/.env'
check "FEISHU_APP_ID已设"      'grep -q "FEISHU_APP_ID=cli_" ~/.hermes/.env'

# ── 3. 网络 ──
echo "── 网络 ──"
check "DeepSeek API可达"       'curl -s -m 5 https://api.deepseek.com/v1/models -H "Authorization: Bearer $(grep DEEPSEEK_API_KEY ~/.hermes/.env | cut -d= -f2)" | grep -q deepseek'

# ── 4. Hermes配置 ──
echo "── Hermes配置 ──"
check "model=deepseek-v4-pro"  'grep -q "deepseek-v4-pro" ~/.hermes/config.yaml'
check "provider=deepseek"      'grep -q "provider: deepseek" ~/.hermes/config.yaml'
check "approvals=off"          'grep -qE "mode: (false|off|none)" ~/.hermes/config.yaml'
check "SOUL.md已预加载"        'grep -q "prefill_messages_file.*SOUL.md" ~/.hermes/config.yaml'

# ── 5. Gateway ──
echo "── Gateway ──"
check "gateway进程运行"        'ps aux | grep "gateway run" | grep -v grep | grep -q hermes'
check "飞书bot在线(websocket)" 'grep -q "FEISHU_CONNECTION_MODE=websocket" ~/.hermes/.env'

# ── 6. 对话测试 ──
echo "── 对话测试 ──"
REPLY=$(timeout 12 hermes chat -q "回一个字：通" 2>&1 || echo "TIMEOUT")
if echo "$REPLY" | grep -q "通"; then
    echo "  ✅ chat测试通过"
    PASS=$((PASS + 1))
else
    echo "  ❌ chat测试失败 — $REPLY"
    FAIL=$((FAIL + 1))
    REPORT="$REPORT\n  FAIL: chat测试"
fi

# ── 结果 ──
echo ""
echo "═══════════════════════════════════════"
echo "  通过: $PASS  失败: $FAIL"
echo "═══════════════════════════════════════"
if [ -n "$REPORT" ]; then
    echo -e "失败项:$REPORT"
fi

[ $FAIL -eq 0 ] && exit 0 || exit 1
