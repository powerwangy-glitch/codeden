#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Codex CLI notify 桥接（实验性）。

Codex 在 ~/.codex/config.toml 配置:
    notify = ["python3", "~/.notch-island/bin/notch-codex-notify.py"]
turn 完成时被调用，JSON 作为最后一个 argv，形如：
    {"type":"agent-turn-complete","turn-id":"...","input-messages":["..."],"last-assistant-message":"..."}
映射成码岛 Stop 事件（agent=codex）。永不报错退出。
"""
import sys, os, json, time

OUT = os.path.join(os.path.expanduser("~"), ".notch-island", "events.jsonl")


def main():
    if len(sys.argv) < 2:
        return
    try:
        n = json.loads(sys.argv[-1])
    except Exception:
        return
    if "turn" not in str(n.get("type", "")):
        return   # 兼容 agent-turn-complete / turn-ended
    user = ""
    msgs = n.get("input-messages") or []
    if msgs:
        user = str(msgs[-1])[:200]
    cwd = os.getcwd()
    evt = {
        "ts": time.time(),
        "session": "codex-" + str(n.get("turn-id") or n.get("thread-id") or "main"),
        "agent": "codex",
        "project": os.path.basename(cwd.rstrip("/")) or "Codex",
        "cwd": cwd,
        "event": "Stop",
        "user": user or None,
        "assistant": (n.get("last-assistant-message") or "")[:200] or None,
        "term": os.environ.get("TERM_PROGRAM"),
        "term_bundle": os.environ.get("__CFBundleIdentifier"),
    }
    evt = {k: v for k, v in evt.items() if v is not None}
    try:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        with open(OUT, "a", encoding="utf-8") as f:
            f.write(json.dumps(evt, ensure_ascii=False) + "\n")
    except Exception:
        pass


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
