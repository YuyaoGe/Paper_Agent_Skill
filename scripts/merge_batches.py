#!/usr/bin/env python3
"""
将 paper_batches/*.json 合并追加到 paper_list.md。

- 自动检测 paper_list.md 中已有的日期，避免重复追加
- 按日期升序追加缺失日期
- 跳过空结果（不写日期标题）
- 不覆盖已有内容（追加模式）

用法:
    python3 merge_batches.py [paper_reader_dir]
    默认: /Users/yuyaoge/Project/paper_reader
"""
from __future__ import annotations

import json
import re
import sys
from datetime import date
from pathlib import Path


DATE_HEADER_RE = re.compile(r"^##\s*(\d{4})年(\d{1,2})月(\d{1,2})日\s*$")


def parse_existing_dates(paper_list_path: Path) -> set[str]:
    if not paper_list_path.exists():
        return set()
    dates = set()
    for line in paper_list_path.read_text(encoding="utf-8").splitlines():
        m = DATE_HEADER_RE.match(line)
        if m:
            y, mo, d = m.groups()
            dates.add(f"{int(y):04d}-{int(mo):02d}-{int(d):02d}")
    return dates


def render_tags(tags: list[str]) -> str:
    return " ".join(f"`[{t}]`" for t in tags if t)


def render_paper(p: dict) -> str:
    title = (p.get("title") or "").strip()
    arxiv = (p.get("arxiv_id") or "").strip()
    gh = (p.get("github") or "").strip()
    abstract = (p.get("abstract") or "").strip().replace("\n", " ")
    tags = render_tags(p.get("tags") or [])

    parts = [f"- **{title}**"]
    if tags:
        parts.append(tags)
    parts.append("—")
    parts.append(f"[{arxiv}](https://arxiv.org/abs/{arxiv})")
    parts.append("|")
    parts.append(f"[GitHub]({gh})")
    line1 = " ".join(parts)
    line2 = f"  > {abstract}"
    return f"{line1}\n{line2}"


def render_date_section(d: str, papers: list[dict]) -> str:
    y, mo, day = d.split("-")
    header = f"## {int(y)}年{int(mo)}月{int(day)}日"
    body = "\n\n".join(render_paper(p) for p in papers)
    return f"{header}\n\n{body}\n"


def main() -> int:
    paper_reader_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/Users/yuyaoge/Project/paper_reader")
    batches_dir = paper_reader_dir / "paper_batches"
    paper_list = paper_reader_dir / "paper_list.md"

    if not batches_dir.exists():
        print(f"[ERROR] 找不到 batch 目录: {batches_dir}", file=sys.stderr)
        return 1

    existing_dates = parse_existing_dates(paper_list)
    print(f"paper_list.md 已包含 {len(existing_dates)} 个日期")

    batch_files = sorted(batches_dir.glob("*.json"))
    candidates: list[tuple[str, list[dict]]] = []

    for bf in batch_files:
        stem = bf.stem
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", stem):
            continue
        if stem in existing_dates:
            continue
        try:
            data = json.loads(bf.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            print(f"[WARN] JSON 解析失败 {bf.name}: {exc}", file=sys.stderr)
            continue
        if not isinstance(data, list):
            print(f"[WARN] 跳过非列表 {bf.name}", file=sys.stderr)
            continue
        if not data:
            continue
        candidates.append((stem, data))

    if not candidates:
        print("无可追加内容。")
        return 0

    candidates.sort(key=lambda x: x[0])
    print(f"待追加 {len(candidates)} 个日期：")
    for d, papers in candidates:
        print(f"  + {d}  ({len(papers)} 篇)")

    new_sections = "\n\n".join(render_date_section(d, papers) for d, papers in candidates)

    if paper_list.exists():
        existing = paper_list.read_text(encoding="utf-8")
        if not existing.endswith("\n"):
            existing += "\n"
        out = existing + "\n" + new_sections
    else:
        out = new_sections

    paper_list.write_text(out, encoding="utf-8")
    total_papers = sum(len(papers) for _, papers in candidates)
    print(f"已写入 {paper_list}")
    print(f"  +{len(candidates)} 个日期, +{total_papers} 篇论文")
    return 0


if __name__ == "__main__":
    sys.exit(main())
