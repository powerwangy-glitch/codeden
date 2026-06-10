#!/bin/bash
# 把码岛发布到 GitHub：创建 codeden 公开仓库 + 推送代码 + 上传 .app 发布包。
# 前提：你已在终端跑过一次 `gh auth login` 完成登录（本脚本不接触你的任何凭据）。
set -e
export PATH="/opt/homebrew/bin:$PATH"
cd "$(dirname "$0")"

REPO="codeden"
DESC="码岛 CodeDen — 把 MacBook 刘海变成 AI 编码助手的实时基地（像素风 + 审批回写 + 怪兽养成）"
ZIP="dist/CodeDen-v0.1.6-mac.zip"   # 纯英文名（GitHub 资产名会丢掉中文字符）

# 确认已登录
gh auth status >/dev/null 2>&1 || { echo "❌ 还没登录。请先在终端运行： gh auth login"; exit 1; }

# 确保发布包存在
[ -f "$ZIP" ] || ./build-app.sh && COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent dist/NotchIsland.app "$ZIP"

# 创建仓库并推送（若已存在则只推送）
if gh repo view "$REPO" >/dev/null 2>&1; then
  git remote get-url origin >/dev/null 2>&1 || gh repo view "$REPO" --json url -q .url | xargs -I{} git remote add origin {}.git
  git push -u origin HEAD:main
else
  gh repo create "$REPO" --public --source=. --remote=origin --description "$DESC" --push
fi

# 发布 release + 上传安装包
gh release view v0.1.6 >/dev/null 2>&1 || \
  gh release create v0.1.6 "$ZIP" \
    --title "码岛 CodeDen v0.1.6" \
    --notes "v0.1.6：修复部分 Codex Desktop 任务运行中但卡片只显示 Codex 的问题；模型请求阶段也会被识别为活跃任务，并读取本地 thread 标题/preview。Claude Desktop / Codex Desktop deep link 跳转继续保留。

安装：下载 zip → 解压 → 拖进 /Applications → 打开 → 跟引导一键接入 Claude Code。
（直接下载的 .app 首次打开若被 Gatekeeper 拦，右键 → 打开。正式分发建议用 dist-notarize.sh 公证。）"

echo "✅ 已发布： $(gh repo view "$REPO" --json url -q .url)"
