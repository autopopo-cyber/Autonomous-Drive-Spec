#!/usr/bin/env python3
"""俊秀心跳 · 飞书查表模块
用法: python3 check_tables.py xiuN
输出: JSON {ctx: str, has_work: bool}
"""
import sys, json, os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, f"{SCRIPT_DIR}/lib")
from feishu_table import FeishuTable

machine = sys.argv[1]
base = "VDifbIjLsaRhYJs5ZTScnotFnBg"
results = {"ctx": "", "has_work": False}

# 1. 任务流水线
try:
    t = FeishuTable(base, "tblH8lFvmAOScAlb")
    rows = t.read_all()
    parts = ["飞书任务流水线:"]
    for r in rows:
        owner = r.get("认领人", "")
        if owner == machine or owner == "待认领":
            parts.append(f"- [{r.get('优先级','')}] {r.get('任务名称','')}: {r.get('描述','')} (状态:{r.get('状态','')})")
            if owner == "待认领":
                t.update_row(r["record_id"], {"认领人": machine, "状态": "🔄 进行中"})
                parts.append("  ↑ 已自动认领")
                results["has_work"] = True
    parts.append("")
    results["ctx"] = "\n".join(parts)
except Exception as e:
    results["ctx"] = f"飞书查表异常: {e}"

# 2. 循环任务
try:
    rt = FeishuTable(base, "tbl2RIZmiZg2xKYR")
    rr = rt.read_all()
    parts = [f"循环任务(负责机器含{machine}):"]
    for r in rr:
        if machine in (r.get("负责机器") or ""):
            parts.append(f"- {r.get('任务名','')} ({r.get('频率','')})")
            if not results["has_work"]:
                results["has_work"] = True
    results["ctx"] += "\n" + "\n".join(parts)
except Exception as e:
    results["ctx"] += f"\n循环表异常: {e}"

print(json.dumps(results, ensure_ascii=False))
