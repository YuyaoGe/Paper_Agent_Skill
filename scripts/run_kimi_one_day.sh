#!/usr/bin/env bash
# 用 Kimi CLI 处理单天的 HuggingFace Daily Papers，写入 paper_batches/YYYY-MM-DD.json
# 用法：./run_kimi_one_day.sh YYYY-MM-DD [paper_reader_dir]
#
# 环境变量：
#   KIMI_BIN  覆盖 Kimi 二进制路径（默认尝试 kimi-legacy → kimi-code → which kimi）

set -u

# 防御 launchd / cron 环境的 PATH 被 path_helper 重写
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

# 探测 Kimi 二进制位置：环境变量 > legacy（无需重新登录）> 新版 kimi-code > $PATH
if [[ -n "${KIMI_BIN:-}" && -x "$KIMI_BIN" ]]; then
  :
elif [[ -x "$HOME/.local/bin/kimi-legacy" ]]; then
  KIMI_BIN="$HOME/.local/bin/kimi-legacy"
elif [[ -x "$HOME/.kimi-code/bin/kimi" ]]; then
  KIMI_BIN="$HOME/.kimi-code/bin/kimi"
elif command -v kimi >/dev/null 2>&1; then
  KIMI_BIN="$(command -v kimi)"
else
  echo "ERROR: cannot find Kimi binary (set KIMI_BIN env var)" >&2
  exit 127
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DATE="${1:-}"
# 优先级：CLI 参数 > 环境变量 PAPER_READER_DIR > 与 skill 同级的 ../paper_reader
PAPER_READER_DIR="${2:-${PAPER_READER_DIR:-$(cd "$SKILL_DIR/.." && pwd)/paper_reader}}"

if [[ -z "$DATE" ]]; then
  echo "Usage: $0 YYYY-MM-DD [paper_reader_dir]" >&2
  exit 2
fi

if ! [[ "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Invalid date: $DATE  (need YYYY-MM-DD)" >&2
  exit 2
fi

BATCH_DIR="$PAPER_READER_DIR/paper_batches"
OUTPUT_FILE="$BATCH_DIR/${DATE}.json"
LOG_DIR="$PAPER_READER_DIR/.kimi_logs"
LOG_FILE="$LOG_DIR/${DATE}.log"

mkdir -p "$BATCH_DIR" "$LOG_DIR"

if [[ -f "$OUTPUT_FILE" ]]; then
  if python3 -c "import json,sys; d=json.load(open('${OUTPUT_FILE}')); sys.exit(0 if isinstance(d,list) else 1)" 2>/dev/null; then
    N=$(python3 -c "import json; print(len(json.load(open('${OUTPUT_FILE}'))))" 2>/dev/null || echo 0)
    if [[ "${N}" -gt 0 ]]; then
      echo "[${DATE}] skip (batch already has ${N} papers)"
      exit 0
    fi
    # 空 [] 时再探一次 HF：若仍为空则跳过（节省 Kimi 调用），否则重跑
    HF_COUNT=$(curl -sfL --max-time 15 "https://huggingface.co/api/daily_papers?date=${DATE}" \
      | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo 0)
    if [[ "${HF_COUNT}" -eq 0 ]]; then
      echo "[${DATE}] skip (existing [] and HF still empty)"
      exit 0
    fi
    echo "[${DATE}] existing [] but HF now has ${HF_COUNT} papers, re-running Kimi"
  fi
fi

PROMPT=$(cat <<EOF
请按 hf-paper-filter 这个 skill 中 SKILL.md 的「Subagent Prompt 模板」流程处理 ${DATE} 这一天的 HuggingFace Daily Papers。

**关键要求：**
- 处理日期：${DATE}
- 输出文件路径：${OUTPUT_FILE}
- 数据来源：https://huggingface.co/api/daily_papers?date=${DATE}
- 严格执行：GitHub 链接验证、GitHub Contents API 代码验证、标签体系、中文摘要（100~200字）
- **必须用 write/file 工具将最终 JSON 数组写入 ${OUTPUT_FILE}**
- 如果当天没有论文或全部被过滤掉，仍需写入一个空数组 []
- JSON 转义：abstract 中的英文双引号必须 \" 转义，中文引号建议改用「」
- 完成后输出确认：✅ 已写入 ${OUTPUT_FILE}，共 N 篇论文

不要修改 paper_list.md（避免并发冲突），只写 batch JSON 文件。
EOF
)

echo "[${DATE}] launching Kimi (${KIMI_BIN##*/}) ... log: ${LOG_FILE}"

cd "$PAPER_READER_DIR" || exit 1

"$KIMI_BIN" --print --quiet \
  --work-dir "$PAPER_READER_DIR" \
  --add-dir "$SKILL_DIR" \
  -p "$PROMPT" \
  > "$LOG_FILE" 2>&1

RC=$?

if [[ -f "$OUTPUT_FILE" ]]; then
  COUNT=$(python3 -c "import json; print(len(json.load(open('${OUTPUT_FILE}'))))" 2>/dev/null || echo "?")
  echo "[${DATE}] done rc=${RC} N=${COUNT}"
else
  echo "[${DATE}] FAIL rc=${RC} (no output file) -- see ${LOG_FILE}"
fi

exit "${RC}"
