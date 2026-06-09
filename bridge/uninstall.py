#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""移除 NotchIsland 的 hook（只删带 notch-bridge.py 标记的项，保留其它全部配置）。"""
import os, json

HOME = os.path.expanduser("~")
SETTINGS = os.path.join(HOME, ".claude", "settings.json")
MARKER = "notch-bridge.py"


def main():
    if not os.path.exists(SETTINGS):
        print("没有 settings.json，无需处理"); return
    with open(SETTINGS, "r", encoding="utf-8") as f:
        data = json.load(f)

    removed = 0
    hooks = data.get("hooks", {})
    for ev in list(hooks.keys()):
        arr = hooks[ev]
        if not isinstance(arr, list):
            continue
        new_arr = []
        for g in arr:
            g_hooks = [h for h in g.get("hooks", []) if MARKER not in (h.get("command") or "")]
            if len(g_hooks) != len(g.get("hooks", [])):
                removed += 1
            if g_hooks:
                g["hooks"] = g_hooks
                new_arr.append(g)
            elif "hooks" not in g:
                new_arr.append(g)
        if new_arr:
            hooks[ev] = new_arr
        else:
            del hooks[ev]

    # 还原 statusLine
    sl = (data.get("statusLine") or {}).get("command", "")
    if "notch-statusline" in sl:
        prev_file = os.path.join(HOME, ".notch-island", ".prev-statusline")
        prev = ""
        if os.path.exists(prev_file):
            prev = open(prev_file).read().strip()
        if prev:
            data["statusLine"] = {"type": "command", "command": prev}
        else:
            data.pop("statusLine", None)
        print("已还原 statusLine")

    with open(SETTINGS, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("已移除 %d 个 NotchIsland hook 项" % removed)


if __name__ == "__main__":
    main()
