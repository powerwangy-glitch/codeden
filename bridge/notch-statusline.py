#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""码岛 statusLine 采集器：从 Claude Code 的 statusLine stdin 取 .rate_limits 写入缓存。
rate_limits 仅 Claude.ai Pro/Max 订阅、且本会话首次 API 响应后出现。读不到就静默跳过。"""
import sys, os, json

def main():
    raw = sys.stdin.read()
    try:
        d = json.loads(raw) if raw.strip() else {}
    except Exception:
        return
    rl = d.get("rate_limits")
    if not rl:
        return
    try:
        cache = os.path.expanduser("~/.notch-island/cache")
        os.makedirs(cache, exist_ok=True)
        with open(os.path.join(cache, "rl.json"), "w") as f:
            json.dump(rl, f)
    except Exception:
        pass

if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
