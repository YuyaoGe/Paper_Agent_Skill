# 批量处理策略

## 日期范围生成

过去3个月（约90天）的日期列表：
```python
from datetime import date, timedelta
start = date(2025, 12, 12)
end = date(2026, 3, 11)
dates = [(start + timedelta(days=i)).isoformat() for i in range((end-start).days+1)]
```

## Subagent 并行策略

每个 subagent 负责约 2 周（14 天）的论文，并行跑约 6-7 个 subagent。

每个 subagent 的任务：
1. 对每个日期运行 `fetch_hf_papers.py`（直接调用 HF API）
2. 自行 review 候选列表（按过滤规则二次筛选）
3. 验证 GitHub 仓库完整性
4. 输出符合条件的论文（markdown 格式），不要写文件，直接返回文本

主 agent 收集所有 subagent 结果，去重后统一写入 paper_list.md。

## 注意事项

- HF API 有时某些日期无论文（周末/节假日），返回空数组属正常
- 同一篇论文可能在不同日期被提交，以 arxiv_id 去重
- 过去3个月大约 1500-2000 篇论文，筛选后预计 150-300 篇候选，人工 review 后 50-100 篇收录
