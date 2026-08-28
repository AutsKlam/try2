#!/usr/bin/env bash
# 列出已备份版本（跳过「写入版本备注哈希」）
# 用法: history.sh [条数，默认20]
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
NOTES="help/版本备注.md"
N="${1:-20}"
HEAD_SHORT="$(git rev-parse --short HEAD)"

note_for() {
  local h="$1"
  if [[ ! -f "$NOTES" ]]; then
    echo ""
    return
  fi
  awk -v h="$h" '
    $0 ~ "^## " h " " {want=1; next}
    want && /^- 备注：/ {
      sub(/^- 备注：/, "", $0)
      print $0
      exit
    }
    want && /^## / {exit}
  ' "$NOTES"
}

echo "| 短哈希 | 时间 | 说明 | 备注 |"
echo "|--------|------|------|------|"

git log -n "$N" --format='%h|%ad|%s' --date=format:'%Y-%m-%d %H:%M' | while IFS='|' read -r hash time subject; do
  case "$subject" in
    写入版本备注哈希*) continue ;;
  esac
  mark=""
  [[ "$hash" == "$HEAD_SHORT" ]] && mark=" **HEAD**"
  remark="$(note_for "$hash")"
  echo "| \`${hash}\`${mark} | ${time} | ${subject} | ${remark} |"
done

echo
echo "撤回示例：版本撤回 <哈希>"
