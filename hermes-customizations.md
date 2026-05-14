# Hermes Agent 全栈定制记录

**最后更新: 2026-05-15 07:00 CST**
**项目: autopopo-cyber/agent-kit**

---

## 总览

Hermes Agent 是一个高度可扩展的 AI agent 平台。我们在其基础上进行了大量定制，使其适配主人的多平台（飞书/微信）、多机器（Tailscale 四机）、多项目（机器人仿真/伴侣平台/图像生成）的复杂需求。

---

## 1. 记忆系统 (Hindsight)

### 1.1 双付费修复

**问题**: Hindsight 的 LLM 调用原本走 OpenRouter → 和 DeepSeek 直连重复付费。

**修复**: 三个覆写点全部改为 DeepSeek 直连。

| 文件 | 改动 | 说明 |
|---|---|---|
| `~/.hermes/hindsight/config.json` | `llm_provider: deepseek` | Hindsight 原生支持 deepseek provider |
| `~/.local/bin/hindsight-launch` | 写入 `HINDSIGHT_API_LLM_PROVIDER=deepseek` | 启动脚本生成 env |
| `~/.hermes/hermes-agent/plugins/memory/hindsight/__init__.py` | `_materialize_embedded_profile_env` 被 NO-OP | 防止插件运行时覆盖配置 |

**当前状态**: LLM → DeepSeek 直连 ✅ | Embeddings → OpenRouter (BGE-M3) ✅ | Reranker → OpenRouter (Cohere) ✅

### 1.2 配置路径

| 配置项 | 路径 |
|---|---|
| Hindsight daemon 端口 | 9177 |
| Hindsight 配置文件 | `~/.hermes/hindsight/config.json` |
| Hindsight 启动脚本 | `~/.local/bin/hindsight-launch` |
| Hindsight 插件 | `~/.hermes/hermes-agent/plugins/memory/hindsight/__init__.py` |
| IDLE_TIMEOUT | 300s (嵌入式 daemon) |

---

## 2. 心跳系统 (Heartbeat)

### 2.1 架构

```
系统 cron (每15分钟)
    │
    ▼
junxiu-heartbeat-feishu.sh
    │
    ├── 第一重: session_active 检查
    │   └── active=1 且时间戳<30分钟 → 静默
    ├── 第二重: 时间戳检查
    │   └── ≤15分钟 → 静默
    └── POST /internal/inject → 飞书注入
```

### 2.2 文件清单

| 文件 | 用途 |
|---|---|
| `~/.local/bin/junxiu-heartbeat-feishu.sh` | 心跳主脚本，双检查 + 注入 |
| `~/.local/bin/junxiu-heartbeat-check.py` | Python 版心跳检查（备用） |
| `~/.local/bin/junxiu-heartbeat.sh` | 早期版本（已弃用） |

### 2.3 防打扰机制

- **`agent:start` 事件**: Hook 写 `session_active=1` → 心跳跳过
- **`agent:end` 事件**: Hook 写 `session_active=0` → 心跳恢复
- **僵死保护**: `session_active=1` 但时间戳 > 30分钟 → 认为僵死 → 仍然注入

### 2.4 历史迭代

| 日期 | 版本 | 改动 |
|---|---|---|
| 2026-05-10 | v1 | 初版，简单时间戳检查，伪装主人语气 |
| 2026-05-12 | v2 | 加时间前缀（凌晨/早上/下午等） |
| 2026-05-15 | v3 | 加 session_active 双检查 + 改语气为心跳自述 |

---

## 3. Hook 系统

### 3.1 自定义 Hooks

| 目录 | 触发事件 | 功能 |
|---|---|---|
| `~/.hermes/hooks/last-message-time/` | `agent:start`, `agent:end` | 写时间戳 + session_active 标记 |
| `~/.hermes/hooks/update-activity-timestamp/` | `agent:start` | 另写时间戳到 workspace（备用） |

### 3.2 输出文件

| 文件 | 写入者 | 格式 |
|---|---|---|
| `/tmp/junxiu_last_msg.txt` | last-message-time hook | Unix 时间戳（秒） |
| `/tmp/junxiu_session_active.txt` | last-message-time hook | "1"（活跃）或 "0"（空闲） |

---

## 4. 模型配置

### 4.1 主模型

| 配置项 | 值 |
|---|---|
| Provider | deepseek |
| Model | deepseek-v4-pro |
| Base URL | https://api.deepseek.com |

### 4.2 API 密钥

| 密钥 | 文件 | 用途 |
|---|---|---|
| DEEPSEEK_API_KEY | `~/.hermes/.env` | 主 LLM |
| OPENROUTER_API_KEY | `~/.hermes/.env` | Hindsight embeddings/reranker |
| API_SERVER_KEY | `~/.hermes/.env` | Gateway API 认证 |

---

## 5. Gateway 配置

### 5.1 平台

| 平台 | 状态 |
|---|---|
| 飞书 (Feishu) | ✅ 主通道 |
| 微信 (Weixin) | ✅ 备用 |
| API Server | ✅ 8642 端口 |

### 5.2 关键配置

| 配置项 | 值 |
|---|---|
| Gateway 端口 | 8642 |
| Dashboard 端口 | 9119 |
| Workspace 端口 | 3002 |
| 启动顺序 | gateway → dashboard → workspace |

---

## 6. 自定义 Skills

位于 `~/.hermes/skills/`，按类别：

| 类别 | Skills |
|---|---|
| 开发运维 | system-time, proxy-auto-setup, memtree-update, session-handoff |
| 机器人 | firefly-navigation, robot-obstacle-simulation, go2-simulation, mujoco-terrain, a2-dog-operations |
| 图像/创作 | comfyui, venice-image-generation, novel-writing-workflow, erotic-fiction-crafting |
| 数据科学 | jupyter-live-kernel |
| GitHub | github-auth, github-repo-management, github-pr-workflow, github-code-review |

---

## 7. 网络与基础设施

### 7.1 Tailscale 四机

| 机器 | IP | 用途 |
|---|---|---|
| 本机 (CVM) | 100.x | Hermes 宿主机 |
| super-server | 100.64.63.98 | RTX2080Ti, MuJoCo 仿真, 换脸 |
| X99 | 100.67.214.106 | RTX2080Ti, ComfyUI |
| 主人机 | 100.76.65.47:2222 | Windows, 主控 |

### 7.2 代理

| 配置 | 值 |
|---|---|
| Mihomo 端口 | 7890 (mixed) |
| Mihomo API | 9090 |
| 配置文件 | `~/.config/mihomo/config.yaml` |
| 推荐节点 | 美国 V1 (直连) |

---

## 8. 关键项目路径

| 项目 | 路径 |
|---|---|
| Simtrack (赛道仿真) | `~/workspace/simtrack/` |
| Test Tracker | `~/test-tracker/` (端口 8080) |
| 伴侣平台 | `~/workspace/a2-companion/` (GitHub: autopopo-cyber/a2-companion) |
| ESP32 HID Bridge | `~/workspace/esp32-hid-bridge/` |
| 小说项目 | `~/workspace/stories/` |
| 俊秀 Wiki | `~/wiki-junxiu/` |

---

## 9. 已发现的坑

| 坑 | 描述 | 解决方案 |
|---|---|---|
| Hindsight 双付费 | LLM 走 OpenRouter 浪费钱 | 三文件 patch → DeepSeek 直连 |
| 心跳闯入对话 | 系统 cron 盲注 | v3: session_active 双检查 |
| Dashboard 崩溃 | 启动顺序错误 | gateway → dashboard → workspace |
| LLM 上下文腐烂 | 大量相似数据幻觉 | LLM 写程序替代直接读写 |
| X99 mihomo 端口 | 默认 7890 不适用 | 实际是 7897，API 9097 |
| ComfyUI seed=-1 | 不兼容 | 用正整数值 |
| Python SimpleHTTP | 不支持 aria2c range | 用 wget 单线程 |

---

## 10. 维护清单

每次升级 Hermes 后需检查：

- [ ] `~/.hermes/hindsight/config.json` — `llm_provider` 是否仍为 `deepseek`
- [ ] `~/.local/bin/hindsight-launch` — 启动脚本是否被覆盖
- [ ] 插件 `plugins/memory/hindsight/__init__.py` — `_materialize_embedded_profile_env` 是否重新激活
- [ ] Hooks `last-message-time/` — HOOK.yaml 和 handler.py 是否完整
- [ ] 心跳脚本 `junxiu-heartbeat-feishu.sh` — 双重检查逻辑 + 语气
- [ ] Gateway 启动顺序 — gateway → dashboard → workspace
