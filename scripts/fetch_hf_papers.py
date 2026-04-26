#!/usr/bin/env python3
"""
HF Daily Papers 筛选脚本
用法: python fetch_hf_papers.py [日期, 默认今天]
示例: python fetch_hf_papers.py 2026-03-11

流程：
1. 从 HF API 拉取当日论文列表
2. 按规则过滤
3. 输出候选列表供人工 review
"""

import sys
import json
import urllib.request
import urllib.error
from datetime import date


# ============================================================
# 过滤规则配置
# ============================================================

# 标题包含以下关键词（不区分大小写）则排除
TITLE_EXCLUDE_KEYWORDS = [
    "benchmark", "benchmarking", "bench",
    "speech",
    "audio",
    "video",
    "3d",
    # 编译器/系统优化/推理加速基础设施类
    "compiler", "cuda", "kernel", "triton",
    "quantization", "quantisation",
    "tpu", "xla",
    "inference acceleration", "inference speed",
    "distillation",  # 知识蒸馏（偏工程向）
]

# 摘要包含以下关键词则排除（比标题宽松，需要更明确的信号）
ABSTRACT_EXCLUDE_PATTERNS = [
    "technical report",
    "we introduce our",          # 模型发布类
    "we present our",
    "in this report",
    "system report",
]

# 摘要必须包含以下关键词之一（确认是 LLM/VLM 领域）
ABSTRACT_REQUIRE_ANY = [
    "large language model", "llm",
    "vision language model", "vlm",
    "multimodal", "multi-modal",
    "language model",
    "foundation model",
    "transformer",
    "reasoning",
    "reinforcement learning",  # RL for LLM
    "instruction tuning", "fine-tuning", "finetuning",
    "alignment",
    "agent",
    "chain-of-thought", "chain of thought",
    "in-context learning",
]


def fetch_daily_papers(date_str: str) -> list:
    """从 HF API 拉取每日论文列表"""
    url = f"https://huggingface.co/api/daily_papers?date={date_str}"
    print(f"📡 正在拉取: {url}")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode())
            return data
    except urllib.error.HTTPError as e:
        print(f"❌ HTTP 错误: {e.code} {e.reason}")
        return []
    except Exception as e:
        print(f"❌ 请求失败: {e}")
        return []


def check_title(title: str) -> tuple[bool, str]:
    """检查标题是否通过过滤，返回 (通过, 原因)"""
    title_lower = title.lower()
    for kw in TITLE_EXCLUDE_KEYWORDS:
        if kw in title_lower:
            return False, f"标题含 '{kw}'"
    return True, ""


def check_abstract(abstract: str) -> tuple[bool, str]:
    """检查摘要是否通过过滤，返回 (通过, 原因)"""
    abstract_lower = abstract.lower()

    # 排除技术报告类
    for pattern in ABSTRACT_EXCLUDE_PATTERNS:
        if pattern in abstract_lower:
            return False, f"摘要含 '{pattern}'"

    # 必须是 LLM/VLM 领域
    matched = [kw for kw in ABSTRACT_REQUIRE_ANY if kw in abstract_lower]
    if not matched:
        return False, "摘要中未找到 LLM/VLM 相关关键词"

    return True, f"匹配关键词: {matched[:3]}"


def extract_github(paper: dict) -> str:
    """从论文数据中提取 GitHub 链接"""
    # HF API 返回的 githubRepo 字段
    repo = paper.get("paper", {}).get("githubRepo", "")
    if repo:
        return repo
    return ""


def filter_papers(papers: list) -> tuple[list, list]:
    """
    过滤论文
    返回 (候选列表, 过滤掉的列表)
    每项包含 {title, arxiv_id, abstract, github, reason}
    """
    candidates = []
    filtered = []

    for item in papers:
        paper = item.get("paper", {})
        title = paper.get("title", "").strip()
        arxiv_id = paper.get("id", "")
        abstract = paper.get("summary", "").strip()
        github = extract_github(item)

        # Step 1: 标题过滤
        ok, reason = check_title(title)
        if not ok:
            filtered.append({"title": title, "arxiv_id": arxiv_id, "reason": reason})
            continue

        # Step 2: 摘要过滤
        ok, reason = check_abstract(abstract)
        if not ok:
            filtered.append({"title": title, "arxiv_id": arxiv_id, "reason": reason})
            continue

        candidates.append({
            "title": title,
            "arxiv_id": arxiv_id,
            "abstract": abstract,
            "github": github,
            "match_reason": reason,
        })

    return candidates, filtered


def print_results(date_str: str, candidates: list, filtered: list, total: int):
    """打印筛选结果"""
    print(f"\n{'='*60}")
    print(f"📅 日期: {date_str}  |  总计: {total} 篇  |  候选: {len(candidates)} 篇  |  已过滤: {len(filtered)} 篇")
    print(f"{'='*60}")

    if not candidates:
        print("\n⚠️  没有通过筛选的论文")
        return

    print(f"\n✅ 候选论文（{len(candidates)} 篇）— 等待人工 review：\n")
    for i, p in enumerate(candidates, 1):
        print(f"[{i}] {p['title']}")
        print(f"    📄 https://arxiv.org/abs/{p['arxiv_id']}")
        if p['github']:
            print(f"    💻 {p['github']}")
        else:
            print(f"    💻 [无 GitHub 链接，需查 PDF]")
        # 打印摘要前 200 字符
        abstract_preview = p['abstract'][:200].replace('\n', ' ')
        if len(p['abstract']) > 200:
            abstract_preview += "..."
        print(f"    📝 {abstract_preview}")
        print()

    print(f"\n❌ 已过滤（{len(filtered)} 篇）：")
    for p in filtered:
        print(f"   - [{p['arxiv_id']}] {p['title'][:60]}... → {p['reason']}")


def main():
    # 解析日期参数
    if len(sys.argv) > 1:
        date_str = sys.argv[1]
    else:
        date_str = date.today().isoformat()

    print(f"🦞 HF Daily Papers 筛选工具")
    print(f"   过滤规则: 排除 benchmark/speech/audio/video/编译器/系统优化/技术报告")
    print(f"   保留: LLM/VLM 核心方法，有 GitHub 代码优先")

    # 拉取数据
    papers = fetch_daily_papers(date_str)
    if not papers:
        print("❌ 未能获取论文列表，退出")
        sys.exit(1)

    print(f"✅ 获取到 {len(papers)} 篇论文")

    # 过滤
    candidates, filtered_out = filter_papers(papers)

    # 打印结果
    print_results(date_str, candidates, filtered_out, len(papers))

    print(f"\n{'='*60}")
    print("⏭️  下一步：人工 review 候选列表，确认后写入 paper_list.md")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    main()
