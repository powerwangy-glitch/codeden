#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 NotchIsland 的 hook 安全合并进 ~/.claude/settings.json。

- 不覆盖、不删除任何已有配置（包括你已装的 Vibe Island hook），只追加。
- 先备份原文件到 settings.json.notch-backup。
- 可重复运行：已安装则跳过（靠命令里的 notch-bridge.py 标记识别）。
"""
import os, json, sys, shutil, time

HOME = os.path.expanduser("~")
SETTINGS = os.path.join(HOME, ".claude", "settings.json")
SRC = os.path.abspath(os.path.join(os.path.dirname(__file__), "notch-bridge.py"))
# 复制到稳定路径，hook 指向这里 → .app 移动/删除不影响已注册的 hook
BIN_DIR = os.path.join(HOME, ".notch-island", "bin")
SCRIPT = os.path.join(BIN_DIR, "notch-bridge.py")
MARKER = "notch-bridge.py"

# 有 matcher 的工具类事件 vs 无 matcher 的生命周期事件
TOOL_EVENTS = ["PreToolUse", "PostToolUse", "PermissionRequest", "Notification"]
LIFE_EVENTS = ["UserPromptSubmit", "Stop", "SubagentStart", "SubagentStop",
               "SessionStart", "SessionEnd"]

COMMAND = "/bin/sh -c '/usr/bin/env python3 \"%s\" >/dev/null 2>&1; exit 0'" % SCRIPT


def load(path):
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def already_has(group_list):
    for g in group_list:
        for h in g.get("hooks", []):
            if MARKER in (h.get("command") or ""):
                return True
    return False


def main():
    # 把桥接脚本复制到稳定路径
    os.makedirs(BIN_DIR, exist_ok=True)
    if os.path.abspath(SRC) != os.path.abspath(SCRIPT):
        shutil.copy2(SRC, SCRIPT)
    os.chmod(SCRIPT, 0o755)

    data = load(SETTINGS)
    os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)

    # 备份
    if os.path.exists(SETTINGS):
        bak = SETTINGS + ".notch-backup"
        shutil.copy2(SETTINGS, bak)
        print("已备份原配置 ->", bak)

    hooks = data.setdefault("hooks", {})
    added = 0
    for ev in TOOL_EVENTS + LIFE_EVENTS:
        arr = hooks.setdefault(ev, [])
        if already_has(arr):
            continue
        hook = {"type": "command", "command": COMMAND}
        if ev == "PermissionRequest":
            hook["timeout"] = 86400          # 审批可长时间阻塞等待你点击
        group = {"hooks": [hook]}
        if ev in TOOL_EVENTS:
            group["matcher"] = "*"
        arr.append(group)
        added += 1

    with open(SETTINGS, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    os.makedirs(os.path.join(HOME, ".notch-island"), exist_ok=True)
    print("已安装 NotchIsland hook：新增 %d 个事件钩子" % added)
    print("脚本路径：", SCRIPT)
    print("重启正在进行的 Claude Code 会话后生效（新会话自动生效）。")


if __name__ == "__main__":
    main()
