#!/usr/bin/env bash
# 用新提交撤回到某历史版本（不改写、不强推）
# 用法: revert.sh <哈希> [备注]
# 退出码: 0 成功/已是该版; 1 失败; 2 冲突; 3 缺参/非法目标
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
NOTES="help/版本备注.md"
TARGET_RAW="${1-}"
REMARK="${2-}"
TIME="$(date '+%Y-%m-%d %H:%M')"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$TARGET_RAW" ]]; then
  echo "用法: revert.sh <哈希> [备注]" >&2
  bash "$SCRIPT_DIR/history.sh" || true
  exit 3
fi

if ! TARGET="$(git rev-parse --short "${TARGET_RAW}^{commit}" 2>/dev/null)"; then
  echo "无法解析目标：${TARGET_RAW}" >&2
  exit 3
fi

if ! git merge-base --is-ancestor "$TARGET" HEAD; then
  echo "目标不是当前分支历史：${TARGET}" >&2
  exit 3
fi

SUBJECT="$(git log -1 --format='%s' "$TARGET")"

# 未提交改动先备份
if ! git diff --quiet || ! git diff --staged --quiet || [[ -n "$(git ls-files --others --exclude-standard | grep -v '^\.cursor' || true)" ]]; then
  bash "$SCRIPT_DIR/git-update.sh" "撤回前自动备份"
fi

git fetch origin
counts="$(git rev-list --left-right --count HEAD...origin/main 2>/dev/null || echo '0	0')"
right="$(echo "$counts" | awk '{print $2}')"
if [[ "${right}" != "0" ]]; then
  if ! git pull --rebase origin main; then
    echo "冲突：请手动解决后重试" >&2
    exit 2
  fi
fi

# 排除备注后是否已无差
if git diff --quiet "$TARGET" HEAD -- . ':(exclude)help/版本备注.md'; then
  echo "已是该版本 ${TARGET}"
  exit 0
fi

git restore --source="$TARGET" --worktree --staged -- . ':(exclude)help/版本备注.md'

# 删除目标之后新增、现仍在 HEAD 的文件
while IFS= read -r path; do
  [[ -z "$path" || "$path" == "help/版本备注.md" ]] && continue
  git rm -f -- "$path" 2>/dev/null || true
done < <(git diff --name-only --diff-filter=A "$TARGET" HEAD)

SUMMARY="撤回至 ${TARGET}（${SUBJECT}）"
if [[ -z "$REMARK" ]]; then
  REMARK="$SUMMARY"
fi
FILES="$(git diff --cached --name-status | paste -sd';' - || echo '见暂存区')"

tmp="$(mktemp)"
{
  echo "# 版本备注"
  echo
  echo "每条对应一次 git 提交。\`git更新\` 会写「更新时间」和「摘要」；也可事后改「备注」。"
  echo
  echo "## 待写入 — ${TIME} — ${SUMMARY}"
  echo
  echo "- 更新时间：${TIME}"
  echo "- 摘要：${SUMMARY}"
  echo "- 文件：${FILES}"
  echo "- 备注：${REMARK}"
  echo
  if [[ -f "$NOTES" ]]; then
    awk 'BEGIN{p=0} /^## /{p=1} p{print}' "$NOTES"
  fi
} >"$tmp"
mv "$tmp" "$NOTES"

git add -- "$NOTES"
git commit -m "$(cat <<EOF
${SUMMARY}

EOF
)"

HASH="$(git rev-parse --short HEAD)"
sed -i "0,/待写入/{s/待写入/${HASH}/}" "$NOTES"
git add -- "$NOTES"
git commit -m "$(cat <<EOF
写入版本备注哈希 ${HASH}

EOF
)"

git push
echo "已撤回至 ${TARGET}｜新备份 ${HASH}｜${TIME}"
