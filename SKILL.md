---
name: hf-paper-filter
description: 每日筛选 HuggingFace 论文列表，过滤掉不感兴趣的 topic，输出候选列表供人工 review，最终写入 paper_list.md。适用于：用户要求筛选某天的 HF 论文、整理 paper_list、批量处理多天论文等场景。
---

# HF Daily Papers 筛选工作流

## 工具

脚本：`scripts/fetch_hf_papers.py`

```bash
python3 fetch_hf_papers.py 2026-03-11   # 指定日期
python3 fetch_hf_papers.py              # 默认今天
```

无需 API key，直接调用 HF 公开接口：`https://huggingface.co/api/daily_papers?date=YYYY-MM-DD`

## 过滤规则（标题关键词，不区分大小写）

**排除的 topic（标题含以下关键词即排除，不区分大小写）：**
- benchmark / benchmarking / bench（含 "bench" 作为单词或前缀）
- speech / audio / video / 3d
- compiler / cuda / kernel / triton / tpu / xla
- quantization / quantisation / distillation（偏工程/基础设施）
- technical report / report（标题含 "report" 字样）
- survey（纯综述不含代码）
- world model（世界模型相关）
- robot / robotics / manipulation / embodied（机器人/具身智能）
- VLA（视觉-语言-动作模型）
- recommendation / recommender（推荐系统）

**注意**：`report` 是字符串匹配，需确认 "report" 出现在标题中（如 "Technical Report"、"xxx Report"）才排除，不是子串误匹配。

**保留的领域：** LLM / VLM 核心方法（reasoning、training、alignment、agent、多模态理解等）

## 完整流程

### Step 1：脚本筛选
```bash
python3 scripts/fetch_hf_papers.py YYYY-MM-DD
```
脚本输出候选列表（含标题、arxiv 链接、GitHub 链接、摘要前 200 字）和过滤列表。

### Step 2：人工 review（必须逐一检查 GitHub）
逐篇检查候选，过滤以下情况：
- 不是 LLM/VLM 核心方法（如纯 3D、image generation、系统优化）
- 纯理论框架无代码
- GitHub 链接缺失
- **GitHub 仓库只有 README，没有实质代码**（最常见问题！）

**GitHub 验证标准**（必须满足其一才保留）：
- 有 `src/`、`scripts/`、`train*.py`、`model*.py` 等训练/推理代码
- 有实质性 `.py` / `.sh` 文件，不只是文档（即使只是调用外部 API 的 agent 框架代码也算）
- Star 数 > 0 且有 commit 记录（不是刚建的空壳）

**注意**：prompting / agent 框架类论文，即使代码只有几个 `.py` 文件调用 OpenAI/Claude 等外部 API，只要有实质代码文件就保留，并打上 `API` 标签。

**操作**：直接点开 GitHub 链接，5秒内能看到代码文件就保留，只有 README/LICENSE 就丢掉。

### Step 3：写入 paper_list.md
路径：`/Users/moonshot/paper_reader/paper_list.md`（追加，不覆盖）

格式：
```markdown
## YYYY年M月D日

- **论文标题** `[标签1]` `[标签2]` — [arxiv_id](https://arxiv.org/abs/id) | [GitHub](https://github.com/...)
  > 中文摘要，100~200字，描述核心贡献、方法、实验结果。
```

示例：
```markdown
- **DAPO: An Open-Source LLM Reinforcement Learning System** `[RL]` — [2503.14476](https://arxiv.org/abs/2503.14476) | [GitHub](https://github.com/xxx/dapo)
  > 提出开源LLM强化学习系统DAPO，针对GRPO训练中的熵崩溃和奖励噪声问题设计了四项关键改进：Clip-Higher策略、动态采样、Token级策略梯度和过滤奖励噪声。在AIME 2024上以50分超越DeepSeek-R1-Zero-32B（47分），完整开源训练代码、数据和模型权重。

- **FlashAttention-3: Fast and Accurate Attention** — [2407.08608](https://arxiv.org/abs/2407.08608) | [GitHub](https://github.com/xxx/flash-attn)
  > （无匹配标签时不显示标签）提出FlashAttention-3...
```

## 批量处理多天

用 subagent 并行处理，**每个 subagent 只负责1天的论文**，最多8个并发。每天一个独立 batch 文件。

**流程概览：**
1. 主 agent 拆分日期范围，为每个 batch 启动一个 subagent
2. **每个 subagent 独立将结果写入 `paper_batches/` 目录下的 JSON 文件**（不写 paper_list.md，避免并发冲突）
3. 所有 subagent 完成后，主 agent 按日期顺序读取所有 batch 文件，合并写入 `paper_list.md`

---

### Subagent Prompt 模板（直接复制使用，替换 `{DATES}` 和 `{OUTPUT_FILE}`）

```
你是一个论文筛选助手。请处理以下日期的 HuggingFace 每日论文，筛选后将结果写入指定文件。

**处理日期：** {DATES}（如：2026-03-05、2026-03-06、2026-03-07）

**输出文件路径：** {OUTPUT_FILE}（如：/Users/moonshot/paper_reader/paper_batches/2026-03-05_07.json）

---

**数据来源：**
- HuggingFace API：`https://huggingface.co/api/daily_papers?date=YYYY-MM-DD`
- API 返回 JSON 结构：`[{ "paper": { "id": "arxiv_id", "title": "...", "summary": "...", "githubRepo": "https://github.com/..." } }, ...]`
- GitHub 链接优先从 `paper.githubRepo` 字段获取；若为空，则尝试从 arxiv HTML 页面中查找

**处理步骤：**
1. 用 web_fetch 拉取指定日期的 HF API 数据：`https://huggingface.co/api/daily_papers?date=YYYY-MM-DD`
2. 对每篇论文读取 `paper.githubRepo` 字段：
   - **非空** → 直接使用该链接
   - **为空** → 用 web_fetch 获取该论文的 arxiv HTML 页面（`https://arxiv.org/html/{arxiv_id}`），在页面内容中搜索 `github.com/` 关键词，取**第一个**出现的完整 GitHub 仓库链接（格式为 `https://github.com/用户名/仓库名`）；若 arxiv 页面也找不到，则丢弃该论文
3. 对有 GitHub 链接的论文执行标题过滤（见下方规则）
4. **对每篇通过标题过滤的论文，调用 GitHub Contents API 验证是否有实质代码**（见 GitHub 代码验证规则）
5. 将通过所有筛选的论文整理为 JSON 数组
6. 用 write 工具将 JSON 写入输出文件路径（**必须使用工具写文件，不能只输出到对话**）

**标题过滤规则（含以下关键词则排除，不区分大小写）：**
bench / benchmark / benchmarking / report / survey / speech / audio / video / 3d / quantization / quantisation / distillation / compiler / cuda / kernel / triton / tpu / xla / world model / robot / robotics / manipulation / embodied / VLA / recommendation / recommender

**GitHub 代码验证规则（每篇论文必须执行，使用 GitHub Contents API 而非页面 fetch）：**
- API 地址：`https://api.github.com/repos/{owner}/{repo}/contents`（从 github 链接解析 owner/repo）
- 用 web_fetch 调用该 API，返回的是仓库根目录文件列表 JSON
- **保留**（满足以下任一条件）：
  - 文件列表中出现 `.py`、`.sh`、`.ipynb` 文件（包括只调用外部 API 的 agent/prompting 框架代码）
  - 存在 `src`、`scripts`、`train`、`model`、`code` 等目录
- **丢弃**（出现以下任一情况）：
  - 文件列表只含 `README.md`、`LICENSE`、`ASSETS`、`assets`、`.gitignore` 等非代码文件
  - API 返回 404（仓库不存在或为空）
  - 仓库名称或描述含 "coming-soon" / "coming_soon" 等
- **不确定时**：保留（宁可多留一篇，不误删有代码的论文）

**`API` 标签判定规则：**
论文方法的核心依赖外部大模型 API（如 OpenAI、Claude、Gemini、GPT-4 等）而非自训练模型时，打 `"API"` 标签。典型特征：
- 代码中直接调用 `openai.chat.completions`、`anthropic.messages` 等
- 论文描述中出现 "we use GPT-4 as backbone"、"powered by Claude" 等
- 框架/方法本身不含模型训练，只做 prompting / agent orchestration

**输出 JSON 格式（写入文件的内容）：**
```json
[
  {
    "date": "YYYY-MM-DD",
    "title": "英文原标题",
    "arxiv_id": "2503.XXXXX",
    "github": "https://github.com/xxx/yyy",
    "abstract": "中文摘要，100~200字，描述核心贡献、方法亮点、实验结果",
    "tags": ["RL"]
  }
]
```

**字段规范：**
1. `title` — 英文原标题，不翻译
2. `github` — 来源于 `paper.githubRepo`（非空时）或 arxiv 页面搜到的第一个 GitHub 链接，**必须非空**，否则不输出该条目
3. `abstract` — 中文，**100~200字**，核心贡献+方法亮点+实验结果，不是简单翻译第一句，不允许短于100字
4. `tags` — 只能从以下选项中选，可多选，无匹配时为空数组 `[]`，**不得自造新标签**：
   - `"RL"` — 强化学习训练/RLVR/GRPO/PPO
   - `"微调"` — SFT/指令微调/PEFT/LoRA
   - `"无需训练"` — training-free/测试时扩展/推理时方法
   - `"长文本"` — 长上下文/长序列处理/超长输入
   - `"VLM"` — 视觉语言模型/多模态理解/图文推理
   - `"MeM"` — Agent的记忆系统
   - `"API"` — 方法核心依赖外部大模型 API（GPT-4/Claude/Gemini 等）而非自训练模型，包括 prompting 框架、agent orchestration 等
   - `"扩散模型"` — 扩散模型相关方法（Diffusion Model、DDPM、Flow Matching、DiT、DLM 等），包括生成、训练、推理加速等

**硬性要求：**
- 没有 `githubRepo`（或为空）的论文**一律不输出**
- 不得自行推断或补全 GitHub 地址
- GitHub 仓库无实质代码的论文**一律不输出**
- **必须用 write 工具将 JSON 写入 `{OUTPUT_FILE}`**，这是最重要的步骤
- 写完后输出一行确认：`✅ 已写入 {OUTPUT_FILE}，共 N 篇论文`
- **JSON 转义警告**：abstract 字段内若含英文双引号 `"`（如引用词语），必须转义为 `\"`；中文引号 `"` `"` 建议改用 `「」` 或删除，否则会破坏 JSON 格式
```

---

### 主 agent 合并流程

所有 subagent 完成后，主 agent 执行以下步骤：

1. 读取 `paper_batches/` 目录下所有 JSON 文件
2. 将所有论文按 `date` 字段排序（从旧到新）
3. 按日期分组，生成 markdown 格式追加到 `paper_list.md`

**markdown 生成规则：**
- 每个新日期输出 `## YYYY年M月D日` 标题
- 每篇论文格式：
  ```
  - **{title}** {tags_str} — [{arxiv_id}](https://arxiv.org/abs/{arxiv_id}) | [GitHub]({github})
    > {abstract}
  ```
- `tags_str`：每个 tag 用反引号包裹，如 `` `[RL]` `[VLM]` ``，无 tag 时省略
- 追加模式写入，不覆盖已有内容

**batch 文件命名规范：**
- 格式：`paper_batches/YYYY-MM-DD.json`（每天一个文件）
- 例：`paper_batches/2026-03-05.json`、`paper_batches/2026-03-06.json`

---

## 每日手动筛选流程（当天论文）

用户亲自筛选当天论文后，**必须同时**：
1. 追加写入 `paper_list.md`
2. 将当天筛选结果**保存到对应的 batch JSON 文件**（`paper_batches/` 目录），确保数据一致

否则下次批量重建 paper_list.md 时，手动筛选的内容会丢失。

**参考格式：**

## 2026年2月17日 

- **Found-RL: foundation model-enhanced reinforcement learning for autonomous driving** `[RL]` `[VLM]` — [2602.10458](https://arxiv.org/abs/2602.10458) | [GitHub](https://github.com/ys-qu/found-rl)
  > 通过基础模型增强自动驾驶强化学习。异步批量推理框架将 VLM 推理与仿真循环解耦；引入 Value-Margin 正则化和优势加权动作引导将 VLM 专家建议蒸馏入 RL 策略。轻量级 RL 模型实现近 VLM 性能（约 500 FPS 实时推理）。