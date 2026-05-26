#!/usr/bin/env bash
# 每天爬取当天 HF Daily Papers，合并到 paper_list.md，并提交推送到远程。
# 用法: ./daily_fetch.sh [YYYY-MM-DD]   不带参数则用今天
#
# 推荐通过 launchd 在每天晚上 22:00 触发：
#   ~/Library/LaunchAgents/com.yuyaoge.paper-daily-fetch.plist

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PAPER_READER_DIR="/Users/yuyaoge/Project/paper_reader"

TARGET_DATE="${1:-$(date "+%Y-%m-%d")}"

LOG_DIR="$PAPER_READER_DIR/.kimi_logs"
mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/daily_${TARGET_DATE}.log"

{
  echo "=============================================="
  echo " 日期: $TARGET_DATE"
  echo " 开始时间: $(date)"
  echo "=============================================="

  echo
  echo "[1/4] 调用 Kimi 处理 $TARGET_DATE …"
  bash "$SCRIPT_DIR/run_kimi_one_day.sh" "$TARGET_DATE" "$PAPER_READER_DIR"
  KIMI_RC=$?
  if [[ "$KIMI_RC" -ne 0 ]]; then
    echo "[!] Kimi 处理失败 rc=$KIMI_RC"
  fi

  echo
  echo "[2/4] 合并 batch 文件 → paper_list.md …"
  python3 "$SCRIPT_DIR/merge_batches.py" "$PAPER_READER_DIR"

  echo
  echo "[3/4] 提交并推送 paper_reader …"
  cd "$PAPER_READER_DIR" || exit 1
  if [[ -n "$(git status --porcelain)" ]]; then
    git add -A
    git commit -m "chore: daily paper update for $TARGET_DATE" || true
    git push origin HEAD || echo "[!] git push 失败"
  else
    echo "  paper_reader 无变更，跳过 push"
  fi

  echo
  echo "[4/4] 提交并推送 Paper_Agent_Skill（如有变更）…"
  cd "$SKILL_DIR" || exit 1
  if [[ -n "$(git status --porcelain)" ]]; then
    git add -A
    git commit -m "chore: scripts update from daily run $TARGET_DATE" || true
    git push origin HEAD || echo "[!] git push 失败"
  else
    echo "  Paper_Agent_Skill 无变更，跳过 push"
  fi

  echo
  echo "结束时间: $(date)"
} 2>&1 | tee -a "$RUN_LOG"
