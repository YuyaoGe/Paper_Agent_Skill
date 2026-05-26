# hf-paper-filter

自动过滤 [HuggingFace Daily Papers](https://huggingface.co/papers)，快速筛选 LLM / VLM 相关高质量论文。

每天 HuggingFace 会推荐数十篇论文，但大部分可能不在你的关注领域。这个工具通过关键词过滤 + 摘要语义过滤，帮你在几秒内缩小范围到真正值得读的那几篇。

## ✨ 特性

- **标题关键词过滤** — 自动排除 benchmark、speech、video、3D、编译器优化、量化蒸馏等不相关主题
- **摘要语义过滤** — 确认论文属于 LLM/VLM 核心领域（reasoning、alignment、agent 等）
- **零依赖** — 纯 Python 标准库，无需安装任何第三方包
- **无需 API Key** — 直接调用 HuggingFace 公开接口

## 🚀 快速开始

```bash
# 筛选指定日期的论文
python3 scripts/fetch_hf_papers.py 2026-04-25

# 筛选今天的论文
python3 scripts/fetch_hf_papers.py
```

输出示例：

```
📅 日期: 2026-04-25  |  总计: 42 篇  |  候选: 12 篇  |  已过滤: 30 篇

✅ 候选论文（12 篇）— 等待人工 review：

[1] DAPO: An Open-Source LLM Reinforcement Learning System
    📄 https://arxiv.org/abs/2503.14476
    💻 https://github.com/xxx/dapo
    📝 We propose DAPO, an open-source RL system for LLM training...
```

脚本会输出候选论文列表（含 arxiv 链接、GitHub 链接、摘要预览）和被过滤掉的论文及原因，方便你快速人工复核。

## 🤖 作为 AI Agent Skill 使用

这个项目同时是一个 **AI Agent Skill**——可以被 AI 编程助手（如 [Kimi Code CLI](https://github.com/anthropics/kimi-code)）作为能力模块加载，实现全自动的每日论文筛选工作流：

1. 调用脚本完成初筛
2. Agent 自动检查 GitHub 仓库是否有实质代码
3. 生成结构化的论文列表（含中文摘要和标签）
4. 支持多天批量并行处理

详见 [`SKILL.md`](./SKILL.md) 了解完整的 Skill 工作流和 Subagent 模板。

## 📁 项目结构

```
hf-paper-filter/
├── README.md                              # 本文件
├── SKILL.md                               # AI Agent Skill 完整工作流文档
├── LICENSE                                # MIT License
├── scripts/
│   ├── fetch_hf_papers.py                 # 核心过滤脚本（纯 Python 初筛）
│   ├── run_kimi_one_day.sh                # 调用 Kimi 处理单天的全流程
│   ├── backfill_papers.sh                 # 批量并行补录指定日期范围
│   ├── merge_batches.py                   # 将 batch JSON 合并到 paper_list.md
│   ├── daily_fetch.sh                     # 每日定时任务（爬取+合并+推送）
│   └── com.yuyaoge.paper-daily-fetch.plist# launchd 配置（每天 22:00 自动运行）
└── references/
    └── batch_process.md                   # 批量处理策略参考
```

## 🛠 自动化工作流（与 [paper_reader](https://github.com/YuyaoGe/paper_reader) 联动）

本项目同时提供一组配合 [Kimi Code CLI](https://moonshotai.github.io/kimi-cli/) 的自动化脚本，实现「每天自动爬取并入库 HuggingFace Daily Papers」。

### 1. 安装 Skill 到 Kimi

```bash
mkdir -p ~/.kimi/skills
ln -sfn "$PWD" ~/.kimi/skills/hf-paper-filter
```

### 2. 历史日期批量补录

并行启动多个 Kimi 子任务（默认并发 6），把缺失的天数一次补齐：

```bash
./scripts/backfill_papers.sh 2026-04-25 2026-05-26 6 /path/to/paper_reader
```

- 已存在的合法 batch 文件会自动跳过
- 每个日期独立写入 `paper_batches/YYYY-MM-DD.json`
- 完成后再用合并脚本一次性整理：

```bash
python3 ./scripts/merge_batches.py /path/to/paper_reader
```

### 3. 每日定时任务

将 launchd 配置安装为用户级任务，每天晚上 22:00 自动爬取当天论文、合并到 `paper_list.md` 并 `git push`：

```bash
cp scripts/com.yuyaoge.paper-daily-fetch.plist ~/Library/LaunchAgents/
launchctl load -w ~/Library/LaunchAgents/com.yuyaoge.paper-daily-fetch.plist
```

手动跑一次测试：

```bash
./scripts/daily_fetch.sh             # 处理今天
./scripts/daily_fetch.sh 2026-05-26  # 处理指定日期
```

日志写入 `paper_reader/.kimi_logs/`。

## ⚙️ 过滤规则

### 排除的主题（标题关键词匹配，不区分大小写）

| 类别 | 关键词 |
|------|--------|
| 评测 | benchmark, benchmarking, bench |
| 多媒体 | speech, audio, video, 3d |
| 系统优化 | compiler, cuda, kernel, triton, tpu, xla |
| 工程向 | quantization, quantisation, distillation |
| 报告/综述 | report, survey |
| 其他 | world model, robot, robotics, embodied, VLA, recommendation |

### 保留的领域

LLM / VLM 核心方法：reasoning, reinforcement learning, alignment, fine-tuning, agent, chain-of-thought, in-context learning, multimodal 等。

## 🔧 自定义

过滤规则定义在 `scripts/fetch_hf_papers.py` 顶部的三个列表中，你可以根据自己的研究方向自由修改：

- `TITLE_EXCLUDE_KEYWORDS` — 标题排除关键词
- `ABSTRACT_EXCLUDE_PATTERNS` — 摘要排除模式
- `ABSTRACT_REQUIRE_ANY` — 摘要必须包含的领域关键词

## License

[MIT](./LICENSE)
