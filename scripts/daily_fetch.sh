#!/usr/bin/env bash
# 自动爬取 HF Daily Papers，合并到 paper_list.md，并提交推送到远程。
#
# 设计原则：
#   - 不抓「今天」：HF 当天列表会持续累积到深夜，今天爬会漏论文
#   - 默认抓「昨天 + 过去 6 天（共 7 天）」：覆盖电脑关机的情况；
#     大多数天已经在 paper_batches/ 里，run_kimi_one_day.sh 会快速跳过
#
# 用法:
#   ./daily_fetch.sh                  # 默认：补过去 7 天（不含今天）
#   ./daily_fetch.sh 2026-05-26       # 只处理指定日期
#   ./daily_fetch.sh yesterday        # 只处理昨天
#   ./daily_fetch.sh today            # 处理今天（不推荐：会漏当天后续提交）
#   ./daily_fetch.sh --days 14        # 自定义回溯窗口
#
# 由 launchd 在登录后及每 2 小时触发：
#   ~/Library/LaunchAgents/com.yuyaoge.paper-daily-fetch.plist

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PAPER_READER_DIR="/Users/yuyaoge/Project/paper_reader"

DAYS=7
TARGET_DATES=()

ARG="${1:-}"
if [[ -z "$ARG" ]]; then
  :  # 使用默认 DAYS=7 回溯
elif [[ "$ARG" == "--days" ]]; then
  DAYS="${2:-7}"
elif [[ "$ARG" == "today" ]]; then
  TARGET_DATES=("$(date "+%Y-%m-%d")")
elif [[ "$ARG" == "yesterday" ]]; then
  TARGET_DATES=("$(date -v-1d "+%Y-%m-%d" 2>/dev/null || date -d "yesterday" "+%Y-%m-%d")")
elif [[ "$ARG" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  TARGET_DATES=("$ARG")
else
  echo "Unknown argument: $ARG" >&2
  exit 2
fi

# 若没显式指定日期，按 DAYS 生成回溯日期序列（昨天往回数 DAYS 天）
if [[ ${#TARGET_DATES[@]} -eq 0 ]]; then
  for ((i=1; i<=DAYS; i++)); do
    d=$(date -v-${i}d "+%Y-%m-%d" 2>/dev/null || date -d "$i days ago" "+%Y-%m-%d")
    TARGET_DATES+=("$d")
  done
fi

# 日志名以最近一次执行的日期标记（便于按天看日志）
LABEL_DATE="${TARGET_DATES[0]}"

LOG_DIR="$PAPER_READER_DIR/.kimi_logs"
mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/daily_${LABEL_DATE}.log"

{
  echo "=============================================="
  echo " 待处理日期 (${#TARGET_DATES[@]} 天): ${TARGET_DATES[*]}"
  echo " 开始时间: $(date)"
  echo "=============================================="

  echo
  echo "[1/4] 逐日调用 Kimi（已存在的会自动跳过）…"
  FAIL_COUNT=0
  for d in "${TARGET_DATES[@]}"; do
    bash "$SCRIPT_DIR/run_kimi_one_day.sh" "$d" "$PAPER_READER_DIR" \
      || FAIL_COUNT=$((FAIL_COUNT+1))
  done
  if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "[!] 有 $FAIL_COUNT 天处理失败（详见各自日志）"
  fi

  echo
  echo "[2/4] 合并 batch 文件 → paper_list.md …"
  python3 "$SCRIPT_DIR/merge_batches.py" "$PAPER_READER_DIR"

  echo
  echo "[3/4] 提交并推送 paper_reader …"
  cd "$PAPER_READER_DIR" || exit 1
  if [[ -n "$(git status --porcelain)" ]]; then
    git add -A
    git commit -m "chore: daily paper update (range ending ${LABEL_DATE})" || true
    git push origin HEAD || echo "[!] git push 失败"
  else
    echo "  paper_reader 无变更，跳过 push"
  fi

  echo
  echo "[4/4] 提交并推送 Paper_Agent_Skill（如有变更）…"
  cd "$SKILL_DIR" || exit 1
  if [[ -n "$(git status --porcelain)" ]]; then
    git add -A
    git commit -m "chore: scripts update from daily run ${LABEL_DATE}" || true
    git push origin HEAD || echo "[!] git push 失败"
  else
    echo "  Paper_Agent_Skill 无变更，跳过 push"
  fi

  echo
  echo "结束时间: $(date)"
} 2>&1 | tee -a "$RUN_LOG"
