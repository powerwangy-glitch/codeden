#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NotchIsland 事件桥接。

被 Claude Code 的各个 hook 调用：从 stdin 读取 hook 的 JSON，必要时读取
transcript 尾部补全「你说的话 / agent 回复」，归一化成一行 JSON 追加到
~/.notch-island/events.jsonl。NotchIsland App 实时 tail 这个文件来更新刘海。

设计原则：永不阻塞、永不报错退出（任何异常都吞掉并 exit 0），不影响 Claude Code。
"""
import sys, os, json, time, uuid

HOME = os.path.expanduser("~")
OUT_DIR = os.path.join(HOME, ".notch-island")
OUT_FILE = os.path.join(OUT_DIR, "events.jsonl")
DECISION_DIR = os.path.join(OUT_DIR, "decisions")
PID_FILE = os.path.join(OUT_DIR, "run", "app.pid")
AGENT = "claude"   # 该桥接专用于 Claude Code；其它 agent 各自的桥接复用本协议

# 审批最长阻塞时间（秒）。App 存活才会等这么久；hook 的 timeout 需 >= 此值。
PERMISSION_MAX_WAIT = 3600


def app_alive():
    """App 是否在运行（读 pidfile + kill 0 探测）。"""
    try:
        with open(PID_FILE) as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
        return True
    except Exception:
        return False


def append_event(evt):
    try:
        os.makedirs(OUT_DIR, exist_ok=True)
        with open(OUT_FILE, "a", encoding="utf-8") as f:
            f.write(json.dumps(evt, ensure_ascii=False) + "\n")
    except Exception:
        pass


def handle_permission(evt, tinput):
    """阻塞等待刘海里的决定，输出 Claude Code 的 PermissionRequest 决定 JSON。
    App 不在 / 超时 → 不输出（exit 0），回退到终端原生权限提示。"""
    rid = "%s-%d-%s" % (evt.get("session", "x"), int(time.time() * 1000), uuid.uuid4().hex[:6])
    evt["request_id"] = rid
    append_event(evt)

    if not app_alive():
        sys.exit(0)   # 没人能点 → 交还给终端

    path = os.path.join(DECISION_DIR, rid + ".json")
    deadline = time.time() + PERMISSION_MAX_WAIT
    while time.time() < deadline:
        if os.path.exists(path):
            try:
                with open(path) as f:
                    dec = json.load(f)
            except Exception:
                dec = {}
            try:
                os.remove(path)
            except Exception:
                pass
            behavior = "allow" if dec.get("behavior") == "allow" else "deny"
            decision = {"behavior": behavior}
            if behavior == "allow" and isinstance(tinput, dict):
                decision["updatedInput"] = tinput   # 按原参数放行
            out = {"hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": decision,
            }}
            print(json.dumps(out))
            sys.exit(0)
        if not app_alive():
            sys.exit(0)   # 等待中 App 退出 → 回退
        time.sleep(0.1)
    sys.exit(0)   # 超时回退


def tool_summary(tool, tinput):
    """把 tool_input 压成一行人类可读摘要。"""
    if not isinstance(tinput, dict):
        return ""
    if tool == "Bash":
        return (tinput.get("command") or "")[:120]
    for k in ("file_path", "path", "notebook_path", "pattern", "url", "query"):
        if k in tinput:
            return str(tinput[k])[:120]
    if tool == "Task":
        return (tinput.get("description") or "")[:120]
    # 兜底：取第一个字符串字段
    for v in tinput.values():
        if isinstance(v, str):
            return v[:120]
    return ""


def read_transcript_tail(path, max_lines=80):
    """从 transcript JSONL 尾部提取最后一条用户文本 + 最后一条 assistant 文本。"""
    last_user, last_assistant = None, None
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()[-max_lines:]
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            typ = obj.get("type")
            msg = obj.get("message") or {}
            content = msg.get("content")
            text = _extract_text(content)
            if typ == "user" and text:
                # 跳过 tool_result 这类伪用户消息
                if not _is_tool_result(content):
                    last_user = text
            elif typ == "assistant" and text:
                last_assistant = text
    except Exception:
        pass
    return last_user, last_assistant


def _extract_text(content):
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = []
        for blk in content:
            if isinstance(blk, dict) and blk.get("type") == "text":
                parts.append(blk.get("text", ""))
        return " ".join(p.strip() for p in parts if p).strip()
    return ""


def _is_tool_result(content):
    if isinstance(content, list):
        return any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content)
    return False


def main():
    raw = sys.stdin.read()
    try:
        hook = json.loads(raw) if raw.strip() else {}
    except Exception:
        hook = {}

    event = hook.get("hook_event_name") or (sys.argv[1] if len(sys.argv) > 1 else "Unknown")
    session = hook.get("session_id") or "unknown"
    cwd = hook.get("cwd") or os.getcwd()
    project = os.path.basename(cwd.rstrip("/")) or cwd
    tool = hook.get("tool_name")
    tinput = hook.get("tool_input")
    message = hook.get("message")
    prompt = hook.get("prompt")

    user, assistant = None, None
    tpath = hook.get("transcript_path")
    if tpath and os.path.exists(tpath):
        user, assistant = read_transcript_tail(tpath)
    if prompt:                      # UserPromptSubmit 直接带 prompt，最准
        user = prompt

    # 终端信息（用于点击跳转）：从环境变量读，hook 子进程继承自所在终端
    TERM_NAMES = {
        "iTerm.app": "iTerm2", "Apple_Terminal": "Terminal", "vscode": "VS Code",
        "ghostty": "Ghostty", "WarpTerminal": "Warp", "Hyper": "Hyper",
        "WezTerm": "WezTerm", "kitty": "kitty", "Tabby": "Tabby", "rio": "Rio",
    }
    tp = os.environ.get("TERM_PROGRAM")
    term = TERM_NAMES.get(tp, tp)
    term_bundle = os.environ.get("__CFBundleIdentifier")

    evt = {
        "ts": time.time(),
        "session": session,
        "agent": AGENT,
        "project": project,
        "cwd": cwd,
        "event": event,
        "tool": tool,
        "tool_summary": tool_summary(tool, tinput) if tool else None,
        "user": user,
        "assistant": assistant,
        "message": message,
        "term": term,
        "term_bundle": term_bundle,
    }
    evt = {k: v for k, v in evt.items() if v is not None}

    # 审批请求：阻塞等待刘海决定并回写（内部会自行写事件 + 退出）
    if event == "PermissionRequest":
        handle_permission(evt, tinput)
        return

    append_event(evt)

    # 关键：始终成功退出，绝不打断 Claude Code
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)
