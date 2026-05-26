#!/usr/bin/env bash
# 批量并行补录指定日期范围的 HuggingFace Daily Papers。
# 用法：./backfill_papers.sh START_DATE END_DATE [CONCURRENCY] [paper_reader_dir]
# 示例：./backfill_papers.sh 2026-04-25 2026-05-25 6

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

START="${1:-}"
END="${2:-}"
CONCURRENCY="${3:-6}"
PAPER_READER_DIR="${4:-/Users/yuyaoge/Project/paper_reader}"

if [[ -z "$START" || -z "$END" ]]; then
  echo "用法: $0 START_DATE END_DATE [CONCURRENCY] [paper_reader_dir]" >&2
  echo "示例: $0 2026-04-25 2026-05-25 6" >&2
  exit 2
fi

BATCH_DIR="$PAPER_READER_DIR/paper_batches"
mkdir -p "$BATCH_DIR"

DATES=()
CURRENT="$START"
while true; do
  DATES+=("$CURRENT")
  if [[ "$CURRENT" == "$END" ]]; then break; fi
  CURRENT=$(date -j -v+1d -f "%Y-%m-%d" "$CURRENT" "+%Y-%m-%d" 2>/dev/null) \
    || CURRENT=$(date -d "$CURRENT + 1 day" "+%Y-%m-%d" 2>/dev/null) \
    || { echo "无法递增日期"; exit 1; }
  if [[ ${#DATES[@]} -gt 365 ]]; then
    echo "范围过大（>365 天），中止" >&2
    exit 1
  fi
done

MISSING=()
SKIPPED=()
for d in "${DATES[@]}"; do
  f="$BATCH_DIR/${d}.json"
  if [[ -f "$f" ]] && python3 -c "import json,sys; d=json.load(open('$f')); sys.exit(0 if isinstance(d,list) else 1)" 2>/dev/null; then
    SKIPPED+=("$d")
    continue
  fi
  MISSING+=("$d")
done

echo "================================================================"
echo "目标范围: $START → $END  共 ${#DATES[@]} 天"
echo "  已存在非空 batch: ${#SKIPPED[@]} 天"
echo "  待处理: ${#MISSING[@]} 天"
echo "  并发度: $CONCURRENCY"
echo "================================================================"

if [[ ${#MISSING[@]} -eq 0 ]]; then
  echo "全部已存在，无需处理。"
  exit 0
fi

printf '%s\n' "${MISSING[@]}" \
  | xargs -P "$CONCURRENCY" -I{} bash "$SCRIPT_DIR/run_kimi_one_day.sh" {} "$PAPER_READER_DIR"

echo "================================================================"
echo "批量补录完成。"

DONE=0
EMPTY=0
FAIL=0
for d in "${MISSING[@]}"; do
  f="$BATCH_DIR/${d}.json"
  if [[ ! -f "$f" ]]; then
    FAIL=$((FAIL+1))
    continue
  fi
  if ! python3 -c "import json,sys; data=json.load(open('$f')); sys.exit(0 if isinstance(data,list) else 1)" 2>/dev/null; then
    FAIL=$((FAIL+1))
    continue
  fi
  N=$(python3 -c "import json; print(len(json.load(open('$f'))))" 2>/dev/null || echo 0)
  if [[ "$N" -eq 0 ]]; then
    EMPTY=$((EMPTY+1))
  else
    DONE=$((DONE+1))
  fi
done

echo "  有论文: $DONE 天 | 空结果: $EMPTY 天 | 失败/无文件: $FAIL 天"
