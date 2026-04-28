#!/bin/bash
# 相邦舰队监管脚本 — 全员可达性、心跳、卡死检测、自动恢复
# Cron: 每10分钟
set -e

MC_URL="${MC_URL:-http://100.80.136.1:3000}"
MC_API_KEY="${MC_API_KEY:-}"
GID="101"
NAME="xiangbang"
LOG="$HOME/xianqin/logs/fleet-supervisor.log"
REPORT="$HOME/xianqin/logs/fleet-report-$(date +%Y%m%d-%H%M).md"

[ -d "$(dirname "$LOG")" ] || mkdir -p "$(dirname "$LOG")"

echo "=== $(date '+%Y-%m-%d %H:%M:%S') 舰队监管 ===" >> "$LOG"

# ─── 1. 查询所有舰队 Agent 状态 ───
AGENTS_JSON=$(curl -sf -H "x-api-key: $MC_API_KEY" "$MC_URL/api/agents" 2>/dev/null)
if [ -z "$AGENTS_JSON" ]; then
    echo "  ❌ MC API 不可达" >> "$LOG"
    exit 1
fi

# ─── 2. 逐节点检查 ───
NOW=$(date +%s)
OFFLINE=""
UNREACHABLE=""
STALE_HEARTBEAT=""

# 节点定义: GID|名称|SSH_HOST|SSH_USER|GW_PORT|ROLE
NODES=(
  "102|白起|100.64.63.98|qin|8644|开发者"
  "103|王翦|100.67.214.106|qin|8644|开发者"
  "104|丞相|100.76.65.47|qinj|8644|开发者"
  "106|俊秀|100.64.63.98|qin|8644|QA审计"
  "107|雪莹|100.67.214.106|qin|8644|QA审计"
  "108|红婳|100.76.65.47|qinj|8644|QA审计"
  "105|萱萱|localhost|agentuser|8644|社交媒体"
)

ISSUES=0
FIXED=0

for node in "${NODES[@]}"; do
    IFS='|' read -r ngid nname nhost nuser nport nrole <<< "$node"
    
    # 检查 2a: Gateway API 可达性 (比SSH更可靠)
    GW_OK=$(curl -sf -m 5 "http://${nhost}:${nport}/health" 2>/dev/null || echo "")
    if [ -n "$GW_OK" ]; then
        echo "  ✅ #$ngid $nname ($nrole): GW ${nhost}:${nport} OK" >> "$LOG"
    else
        # 尝试 8642 端口
        GW_OK=$(curl -sf -m 5 "http://${nhost}:8642/health" 2>/dev/null || echo "")
        if [ -n "$GW_OK" ]; then
            echo "  ⚠️ #$ngid $nname ($nrole): GW ${nhost}:8642 OK (persona 8644 离线)" >> "$LOG"
            UNREACHABLE="$UNREACHABLE\n  - #$ngid $nname: persona gateway $nport 离线, 主GW 8642 正常"
            ISSUES=$((ISSUES + 1))
        else
            echo "  ❌ #$ngid $nname ($nrole): ${nhost} 完全不可达" >> "$LOG"
            UNREACHABLE="$UNREACHABLE\n  - #$ngid $nname ($nrole): ${nhost} 完全不可达 (GW + SSH)"
            ISSUES=$((ISSUES + 1))
        fi
    fi
    
    # 检查 2b: SSH 可达性 (仅尝试，不阻塞)
    if [ "$nhost" != "localhost" ]; then
        SSH_OK=$(ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=no \
            "${nuser}@${nhost}" "hostname" 2>/dev/null || echo "")
        if [ -z "$SSH_OK" ]; then
            # SSH 不可达但 GW 可能可达 — 记录但不阻塞
            echo "     ⚠️ SSH 不可达 (${nuser}@${nhost})" >> "$LOG"
        fi
    fi
    
    # 检查 2c: 清理该节点的残留锁文件 (如果SSH可达)
    if [ -n "$SSH_OK" ] && [ "$nhost" != "localhost" ]; then
        STALE_LOCKS=$(ssh -o ConnectTimeout=3 -o BatchMode=yes "${nuser}@${nhost}" \
            "ls ~/.xianqin/mc-poll-*.lock ~/.xianqin/qa-poll-*.lock 2>/dev/null | while read f; do
                age=\$(( $(date +%s) - \$(stat -c %Y \"\$f\" 2>/dev/null || echo 0) ))
                [ \$age -gt 600 ] && echo \"\$f (age: \${age}s)\"
             done" 2>/dev/null || echo "")
        if [ -n "$STALE_LOCKS" ]; then
            ssh -o ConnectTimeout=3 -o BatchMode=yes "${nuser}@${nhost}" \
                "find ~/.xianqin/ -name '*.lock' -mmin +10 -delete" 2>/dev/null
            echo "     🔧 清理残留锁文件: $STALE_LOCKS" >> "$LOG"
            FIXED=$((FIXED + 1))
        fi
    fi
done

# ─── 3. 检查心跳 — 超过10分钟未更新 = 可能卡死 ───
echo "$AGENTS_JSON" | python3 -c "
import json, sys, time
data = json.load(sys.stdin)
agents = data if isinstance(data, list) else data.get('agents', [])
now = int(time.time())
for a in agents:
    gid = a.get('global_id', '')
    if not gid or not gid.isdigit(): continue
    gid = int(gid)
    if gid < 101 or gid > 108: continue
    ls = a.get('last_seen', 0) or 0
    gap = now - ls if ls else 99999
    status = a.get('status', 'unknown')
    name = a.get('name', '?')
    if gap > 600:  # 10分钟
        print(f'HEARTBEAT_LATE|{gid}|{name}|{status}|gap={gap}s')
" 2>/dev/null | while IFS='|' read -r tag agid aname astatus agap; do
    echo "  💔 #$agid $aname: 心跳延迟 $agap, MC状态=$astatus" >> "$LOG"
    STALE_HEARTBEAT="$STALE_HEARTBEAT\n  - #$agid $aname: $agap"
    ISSUES=$((ISSUES + 1))
done

# ─── 4. 任务流停滞检测 — inbox/assigned 堆积 ───
# 核心诊断: 如果大量 assigned_to 已设置但 status 长时间停留在 inbox/assigned
# 原因可能是 mc-poll.py 查询条件与实际状态不匹配
STAGNATION=$(curl -sf -H "x-api-key: $MC_API_KEY" \
    "$MC_URL/api/tasks?status=inbox&limit=50" 2>/dev/null | \
    python3 -c "
import json, sys, time
tasks = json.loads(sys.stdin.read() or '[]')
tasks = tasks if isinstance(tasks, list) else tasks.get('tasks', [])

now = int(time.time())
stagnant_inbox = 0
stagnant_assigned = 0
oldest_age = 0
oldest_id = '?'

for t in tasks:
    status = t.get('status', '')
    assigned = t.get('assigned_to', '')
    updated = t.get('updated_at', 0) or 0
    age = now - updated
    
    # Check if it's dispatched (has assigned_to) but stuck in inbox
    if assigned and status == 'inbox' and age > 3600:
        stagnant_inbox += 1
        if age > oldest_age:
            oldest_age = age
            oldest_id = t['id']
    
    # Also check assigned tasks
    if assigned and status == 'assigned' and age > 3600:
        stagnant_assigned += 1
        if age > oldest_age:
            oldest_age = age
            oldest_id = t['id']

print(f'STAGNANT_INBOX={stagnant_inbox}|STAGNANT_ASSIGNED={stagnant_assigned}|OLDEST_ID={oldest_id}|OLDEST_AGE={oldest_age}h')
" 2>/dev/null)

if [ -n "$STAGNATION" ]; then
    eval "$STAGNATION"
    if [ "${STAGNANT_INBOX:-0}" -gt 3 ] || [ "${STAGNANT_ASSIGNED:-0}" -gt 0 ]; then
        echo "  🔴 任务流停滞: ${STAGNANT_INBOX} inbox + ${STAGNANT_ASSIGNED} assigned 任务停滞 >1h, 最老 #${OLDEST_ID} ($(($OLDEST_AGE/3600))h)" >> "$LOG"
        echo "     可能原因: mc-poll.py status 查询条件与实际 MC 状态不匹配" >> "$LOG"
        echo "     建议: 检查 mc-poll.py 查询 status= 字段是否与任务实际状态一致" >> "$LOG"
        ISSUES=$((ISSUES + 1))
    fi
fi

# ─── 5. 检查卡死任务 — in_progress 超过 30 分钟无更新 ───
STUCK=$(curl -sf -H "x-api-key: $MC_API_KEY" \
    "$MC_URL/api/tasks?status=in_progress&limit=20" 2>/dev/null | \
    python3 -c "
import json, sys, time
tasks = json.loads(sys.stdin.read() or '[]')
tasks = tasks if isinstance(tasks, list) else tasks.get('tasks', [])
now = int(time.time())
for t in tasks:
    updated = t.get('updated_at', 0) or 0
    if now - updated > 1800:
        print(f'#{t[\"id\"]} [{t.get(\"ticket_ref\",\"?\")}] {t[\"title\"][:60]} assigned={t.get(\"assigned_to\",\"?\")}')
" 2>/dev/null)

if [ -n "$STUCK" ]; then
    echo "  🔴 卡死任务 (>30min):" >> "$LOG"
    echo "$STUCK" | while read line; do
        echo "     $line" >> "$LOG"
    done
fi

# ─── 6. Artifact 真相验证 — 对抗幻觉 ───
# 不信任 Agent 自述的 "已完成", 只信任可验证产物(Artifact)
echo "  🔍 Artifact 验证..." >> "$LOG"
HALLUCINATION=""

# 5a: 验证 review 任务 — 必须有 git commit + result 文件
REVIEW_TASKS=$(curl -sf -H "x-api-key: $MC_API_KEY" \
    "$MC_URL/api/tasks?status=review&limit=20" 2>/dev/null | \
    python3 -c "
import json, sys
tasks = json.loads(sys.stdin.read() or '[]')
tasks = tasks if isinstance(tasks, list) else tasks.get('tasks', [])
for t in tasks:
    print(f'{t[\"id\"]}|{t.get(\"ticket_ref\",\"?\")}|{t[\"title\"][:60]}|{t.get(\"assigned_to\",\"?\")}')
" 2>/dev/null)

if [ -n "$REVIEW_TASKS" ]; then
    echo "$REVIEW_TASKS" | while IFS='|' read -r tid tref ttitle tdev; do
        echo "     审查 review 任务 #$tid $tref ($tdev)" >> "$LOG"
        
        # 检查: 对应节点的 git log 是否有近期commit
        # 通过 MC agents 表找节点 → 尝试 git log
        HAS_ARTIFACT=0
        for node_info in "${NODES[@]}"; do
            IFS='|' read -r ngid nname nhost nuser nport nrole <<< "$node_info"
            if [ "$nname" = "$tdev" ] || [ "$ngid" = "${tdev}" ]; then
                # 尝试通过GW API获取git状态（如果节点有对应端点）
                GIT_CHECK=$(curl -sf -m 5 "http://${nhost}:${nport}/api/git/log?limit=5" 2>/dev/null || echo "")
                if [ -n "$GIT_CHECK" ]; then
                    echo "        git log: $(echo "$GIT_CHECK" | head -1)" >> "$LOG"
                    HAS_ARTIFACT=1
                fi
                break
            fi
        done
        
        if [ $HAS_ARTIFACT -eq 0 ]; then
            echo "     ⚠️ #$tid $tref: review 但无 git 产物 — 可能是幻觉" >> "$LOG"
            HALLUCINATION="$HALLUCINATION\n  - #$tid $tref ($tdev): review 状态但无 git 产物"
            ISSUES=$((ISSUES + 1))
        fi
    done
fi

# 5b: 验证 done 任务 — 必须有 QA audit 文件
DONE_TASKS=$(curl -sf -H "x-api-key: $MC_API_KEY" \
    "$MC_URL/api/tasks?status=done&project_id=2&limit=10" 2>/dev/null | \
    python3 -c "
import json, sys
tasks = json.loads(sys.stdin.read() or '[]')
tasks = tasks if isinstance(tasks, list) else tasks.get('tasks', [])
for t in tasks:
    print(f'{t[\"id\"]}|{t.get(\"ticket_ref\",\"?\")}|{t[\"title\"][:60]}')
" 2>/dev/null)

if [ -n "$DONE_TASKS" ]; then
    echo "$DONE_TASKS" | while IFS='|' read -r tid tref ttitle; do
        echo "     审查 done 任务 #$tid $tref" >> "$LOG"
        
        # 检查: wiki-{GID}/raw/qa-audit-{tid}.md 是否存在?
        AUDIT_FOUND=0
        for ngid in 106 107 108; do  # QA agents
            for nhost in "100.64.63.98" "100.67.214.106" "100.76.65.47"; do
                AUDIT_CHECK=$(curl -sf -m 3 "http://${nhost}:8644/api/wiki/raw/qa-audit-${tid}.md" 2>/dev/null || echo "")
                if [ -n "$AUDIT_CHECK" ]; then
                    echo "        审计文件: wiki-$ngid/raw/qa-audit-$tid.md 存在" >> "$LOG"
                    AUDIT_FOUND=1
                    break 2
                fi
            done
        done
        
        if [ $AUDIT_FOUND -eq 0 ]; then
            echo "     ⚠️ #$tid $tref: done 但无 QA audit 文件 — 可能是幻觉" >> "$LOG"
            HALLUCINATION="$HALLUCINATION\n  - #$tid $tref: done 状态但无 QA 审计文件"
            ISSUES=$((ISSUES + 1))
        fi
    done
fi

# ─── 7. 尝试自动恢复 ───
# 5a: 本地 persona gateway (萱萱 #105)
LOCAL_GW=$(curl -sf -m 3 "http://127.0.0.1:8644/health" 2>/dev/null || echo "")
if [ -z "$LOCAL_GW" ]; then
    echo "  🔧 尝试重启本地 persona gateway (8644)..." >> "$LOG"
    # 启动萱萱的gateway（如果hermes profile可用）
    cd "$HOME/.hermes/hermes-agent"
    source venv/bin/activate 2>/dev/null
    hermes profile use xuanxuan 2>/dev/null && \
        nohup python -m hermes_cli.main gateway run --port 8644 > /tmp/gw-xuanxuan.log 2>&1 &
    echo "     已尝试启动 xuanxuan gateway" >> "$LOG"
fi

# ─── 7. 生成监管报告 ───
{
    echo "# 舰队监管报告 $(date '+%Y-%m-%d %H:%M')"
    echo ""
    echo "## 发现 $ISSUES 个问题，已自动修复 $FIXED 个"
    echo ""
    if [ -n "$UNREACHABLE" ]; then
        echo "## ❌ 不可达"
        echo -e "$UNREACHABLE"
        echo ""
    fi
    if [ -n "$STALE_HEARTBEAT" ]; then
        echo "## 💔 心跳延迟 (>10min)"
        echo -e "$STALE_HEARTBEAT"
        echo ""
    fi
    if [ -n "$STUCK" ]; then
        echo "## 🔴 卡死任务 (>30min in_progress)"
        echo '```'
        echo "$STUCK"
        echo '```'
        echo ""
    fi
    if [ -n "$HALLUCINATION" ]; then
        echo "## 🌀 Artifact 验证失败 (MC状态与产物不一致 → 疑似幻觉)"
        echo -e "$HALLUCINATION"
        echo ""
    fi
    if [ $ISSUES -eq 0 ]; then
        echo "## ✅ 全舰队健康"
        echo ""
    fi
    echo "---"
    echo "*自动生成 by 相邦 fleet-supervisor.sh | Artifact验证=ON*"
} > "$REPORT"

echo "  📋 报告: $REPORT ($ISSUES issues, $FIXED fixed)" >> "$LOG"
