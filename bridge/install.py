#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 NotchIsland 的 hook 安全合并进 ~/.claude/settings.json。

- 不覆盖、不删除任何已有配置（包括你已装的 Vibe Island hook），只追加。
- 先备份原文件到 settings.json.notch-backup。
- 可重复运行：已安装则跳过（靠命令里的 notch-bridge.py 标记识别）。
"""
import os, json, sys, shutil, time, shlex

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
               "SessionStart", "SessionEnd", "PreCompact"]

# Keep stdout intact: Claude Code reads PermissionRequest decisions from stdout.
# Stderr is still swallowed so bridge failures never interrupt the host session.
COMMAND = "/bin/sh -c '/usr/bin/env python3 \"%s\" 2>/dev/null; exit 0'" % SCRIPT


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


def refresh_existing(group_list, event_name):
    """Bring previously installed NotchIsland hooks up to the current command."""
    changed = 0
    for g in group_list:
        for h in g.get("hooks", []):
            if MARKER not in (h.get("command") or ""):
                continue
            if h.get("command") != COMMAND:
                h["command"] = COMMAND
                changed += 1
            if event_name == "PermissionRequest" and h.get("timeout") != 86400:
                h["timeout"] = 86400
                changed += 1
    return changed


def setup_statusline(data):
    """安装 statusLine 采集器：抓 .rate_limits 写码岛缓存，并链式调用原有 statusLine（保留 Vibe 等）。"""
    py_src = os.path.join(os.path.dirname(__file__), "notch-statusline.py")
    py_dst = os.path.join(BIN_DIR, "notch-statusline.py")
    sh_dst = os.path.join(BIN_DIR, "notch-statusline.sh")
    if os.path.exists(py_src) and os.path.abspath(py_src) != os.path.abspath(py_dst):
        shutil.copy2(py_src, py_dst)
    os.chmod(py_dst, 0o755)

    prev = (data.get("statusLine") or {}).get("command", "")
    if "notch-statusline" in prev:
        prev = ""  # 已是我们的，避免自链
    # 记下原 statusLine 以便卸载时还原
    if prev:
        with open(os.path.join(HOME, ".notch-island", ".prev-statusline"), "w") as f:
            f.write(prev)

    chain = ('printf "%s" "$input" | eval "$PREV"' if prev else "")
    sh = f"""#!/bin/bash
input=$(cat)
printf '%s' "$input" | /usr/bin/env python3 "{py_dst}" 2>/dev/null
PREV={json.dumps(prev)}
{chain}
"""
    with open(sh_dst, "w") as f:
        f.write(sh)
    os.chmod(sh_dst, 0o755)
    data["statusLine"] = {"type": "command", "command": sh_dst}


def setup_codex():
    """实验性：把 notify 钩子写入 ~/.codex/config.toml（已有 notify 则跳过，不覆盖）。"""
    cfg = os.path.join(HOME, ".codex", "config.toml")
    if not os.path.isdir(os.path.dirname(cfg)):
        print("未发现 ~/.codex，跳过 Codex 接入")
        return
    src = os.path.join(os.path.dirname(__file__), "notch-codex-notify.py")
    dst = os.path.join(BIN_DIR, "notch-codex-notify.py")
    if os.path.exists(src) and os.path.abspath(src) != os.path.abspath(dst):
        shutil.copy2(src, dst)
    os.chmod(dst, 0o755)
    body = ""
    if os.path.exists(cfg):
        with open(cfg) as f:
            body = f.read()
    import re
    m = re.search(r"^notify\s*=\s*(\[.*?\])\s*$", body, re.M)
    if os.path.exists(cfg):
        shutil.copy2(cfg, cfg + ".notch-backup")
    chain = os.path.join(BIN_DIR, "codex-notify-chain.sh")
    def recover_orig_from_chain():
        if not os.path.exists(chain):
            return []
        try:
            lines = open(chain).read().splitlines()
        except Exception:
            return []
        for line in lines:
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or "notch-codex-notify.py" in stripped or stripped == "wait":
                continue
            if stripped.endswith("&"):
                stripped = stripped[:-1].strip()
            stripped = stripped.replace('"$@"', "").replace("'$@'", "").strip()
            try:
                return shlex.split(stripped)
            except Exception:
                return []
        return []

    def clean_orig_notify(orig):
        """Avoid chaining NotchIsland into itself via Codex Computer Use previous-notify."""
        if not orig:
            return []
        if len(orig) == 1 and orig[0] == chain:
            orig = recover_orig_from_chain()
        out = []
        i = 0
        while i < len(orig):
            if orig[i] == "--previous-notify" and i + 1 < len(orig):
                i += 2
                continue
            out.append(orig[i])
            i += 1
        return [x for x in out if x != chain]
    if m:
        # 已有 notify（如 Codex Computer Use）→ 链式：先原命令，再码岛
        try:
            orig = clean_orig_notify(json.loads(m.group(1)))
        except Exception:
            print("⚠️ 无法解析现有 notify，跳过"); return
        if not orig:
            orig_cmd = ""
        else:
            orig_cmd = " ".join("'%s'" % a.replace("'", "'\\''") for a in orig)
        with open(chain, "w") as f:
            f.write('#!/bin/bash\n# 码岛链式 notify：保留原有 notify + 码岛桥接\n')
            if orig_cmd:
                f.write('%s "$@" &\n' % orig_cmd)
            f.write('/usr/bin/env python3 "%s" "$@" &\nwait\n' % dst)
        os.chmod(chain, 0o755)
        body = re.sub(r"^notify\s*=\s*\[.*?\]\s*$",
                      'notify = ["%s"]' % chain, body, count=1, flags=re.M)
        with open(cfg, "w") as f:
            f.write(body)
        if orig:
            print("已安装链式 Codex notify（原 notify 保留：%s）" % orig[0].split("/")[-1])
        else:
            print("已安装 Codex notify 桥接（已清理自引用链）")
    else:
        with open(cfg, "a") as f:
            f.write('\n# NotchIsland (码岛) Codex 桥接\nnotify = ["python3", "%s"]\n' % dst)
        print("已安装 Codex notify 桥接（备份: config.toml.notch-backup）")


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
    refreshed = 0
    for ev in TOOL_EVENTS + LIFE_EVENTS:
        arr = hooks.setdefault(ev, [])
        if already_has(arr):
            refreshed += refresh_existing(arr, ev)
            continue
        hook = {"type": "command", "command": COMMAND}
        if ev == "PermissionRequest":
            hook["timeout"] = 86400          # 审批可长时间阻塞等待你点击
        group = {"hooks": [hook]}
        if ev in TOOL_EVENTS:
            group["matcher"] = "*"
        arr.append(group)
        added += 1

    # 安装额度采集 statusLine（链式保留原有）
    setup_statusline(data)

    with open(SETTINGS, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    os.makedirs(os.path.join(HOME, ".notch-island"), exist_ok=True)
    print("已安装 NotchIsland hook：新增 %d 个事件钩子" % added)
    if refreshed:
        print("已刷新 %d 个既有码岛 hook 命令" % refreshed)
    print("已安装额度采集 statusLine（链式保留原有 statusLine）")
    if "--codex" in sys.argv:
        setup_codex()
    print("脚本路径：", SCRIPT)
    print("重启正在进行的 Claude Code 会话后生效（新会话自动生效）。")


if __name__ == "__main__":
    main()
