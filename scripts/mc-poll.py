#!/usr/bin/env python3
"""MC Task Poller v3 — uses global_id only (no names)."""
import json, sys, os, urllib.request

GID = os.environ.get('MC_AGENT_GLOBAL_ID', '')
MC = os.environ.get('MC_URL', 'http://100.80.136.1:3000')
KEY = os.environ.get('MC_API_KEY', '')

if not GID:
    sys.exit(0)

try:
    # Bypass proxy for localhost — urllib goes through system proxy otherwise
    proxy_handler = urllib.request.ProxyHandler({})
    opener = urllib.request.build_opener(proxy_handler)
    
    # Query by global_id — no status filter, pick up both inbox and assigned
    # MC dispatch moves inbox→assigned, so we need to catch both
    url = f"{MC}/api/tasks?assigned_to={GID}&limit=5"
    req = urllib.request.Request(url)
    req.add_header('x-api-key', KEY)
    with opener.open(req, timeout=10) as resp:
        data = json.loads(resp.read())
    
    tasks = data if isinstance(data, list) else data.get('tasks', [])
    # Filter to actionable statuses only
    actionable = [t for t in tasks if t.get('status') in ('inbox', 'assigned')]
    if not actionable:
        sys.exit(0)
    
    t = actionable[0]
    print(json.dumps({
        'id': t['id'],
        'title': t.get('title', '')[:120],
        'description': t.get('description', '') or ''
    }, ensure_ascii=False))

except Exception:
    sys.exit(0)
