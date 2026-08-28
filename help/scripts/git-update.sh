#!/usr/bin/env bash
# 备份当前改动：对齐远程 → 暂存 → 写版本备注 → 双提交 → push
# 用法: git-update.sh [备注]
# 退出码: 0 成功/无需更新; 1 失败; 2 冲突需人工
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
NOTES="help/版本备注.md"
REMARK="${1-}"
TIME="$(date '+%Y-%m-%d %H:%M')"

ensure_gitignore() {
  if [[ ! -f .gitignore ]] || ! grep -qxF '.cursor/' .gitignore 2>/dev/null; then
    mkdir -p "$(dirname .gitignore)"
    touch .gitignore
    grep -qxF '.cursor/' .gitignore || echo '.cursor/' >> .gitignore
  fi
}

auto_summary() {
  local list
  list="$(git status --porcelain | awk '{print $NF}' | grep -v '^\.cursor' | paste -sd',' - || true)"
  if [[ -z "${list}" ]]; then
    echo "无文件变更"
  else
    echo "备份：${list}"
  fi
}

sync_remote() {
  git fetch origin
  local counts left right
  counts="$(git rev-list --left-right --count HEAD...origin/main 2>/dev/null || echo '0	0')"
  left="$(echo "$counts" | awk '{print $1}')"
  right="$(echo "$counts" | awk '{print $2}')"
  if [[ "${right}" != "0" ]]; then
    if ! git pull --rebase origin main; then
      echo "冲突：请手动解决后重试" >&2
      exit 2
    fi
  fi
}

has_changes() {
  ! git diff --quiet || ! git diff --staged --quiet || [[ -n "$(git ls-files --others --exclude-standard | grep -v '^\.cursor' || true)" ]]
}

only_ahead() {
  local counts left right
  counts="$(git rev-list --left-right --count HEAD...origin/main 2>/dev/null || echo '0	0')"
  left="$(echo "$counts" | awk '{print $1}')"
  right="$(echo "$counts" | awk '{print $2}')"
  [[ "${left}" != "0" && "${right}" == "0" ]]
}

insert_note() {
  local hash_placeholder="$1" summary="$2" remark="$3" files="$4"
  local tmp
  tmp="$(mktemp)"
  {
    echo "# 版本备注"
    echo
    echo "每条对应一次 git 提交。\`git更新\` 会写「更新时间」和「摘要」；也可事后改「备注」。"
    echo
    echo "## ${hash_placeholder} — ${TIME} — ${summary}"
    echo
    echo "- 更新时间：${TIME}"
    echo "- 摘要：${summary}"
    echo "- 文件：${files}"
    echo "- 备注：${remark}"
    echo
    # 保留旧正文（跳过原文件开头到第一个 ## 之前的标题块，从第一个 ## 起）
    if [[ -f "$NOTES" ]]; then
      awk 'BEGIN{p=0} /^## /{p=1} p{print}' "$NOTES"
    fi
  } >"$tmp"
  mkdir -p help
  mv "$tmp" "$NOTES"
}

ensure_gitignore
sync_remote

if ! has_changes; then
  if only_ahead; then
    git push
    echo "已推送本地超前提交｜${TIME}"
    exit 0
  fi
  echo "没有新改动，无需更新"
  exit 0
fi

SUMMARY="$(auto_summary)"
if [[ -z "$REMARK" ]]; then
  REMARK="$SUMMARY"
fi
FILES="$(git status --porcelain | awk '{print $NF}' | grep -v '^\.cursor' | paste -sd'、' - || echo '（见 diff）')"

git add -u
# 未跟踪项目文件（排除 .cursor）
while IFS= read -r -d '' f; do
  git add -- "$f"
done < <(git ls-files -z --others --exclude-standard | grep -zv '^\.cursor' || true)

insert_note "待写入" "$SUMMARY" "$REMARK" "$FILES"
git add -- "$NOTES"

git commit -m "$(cat <<EOF
${SUMMARY}

EOF
)"

HASH="$(git rev-parse --short HEAD)"
# 替换第一条待写入
if grep -q '待写入' "$NOTES"; then
  sed -i "0,/待写入/{s/待写入/${HASH}/}" "$NOTES"
  git add -- "$NOTES"
  git commit -m "$(cat <<EOF
写入版本备注哈希 ${HASH}

EOF
)"
fi

git push
echo "已备份 ${HASH}｜${TIME}｜${SUMMARY}"
