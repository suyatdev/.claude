"""memsearch CLI — the agent's entry point (driven via Bash). Compact output,
provenance always attached, errors to stderr with exit 1."""
from __future__ import annotations

import argparse
import sys
from functools import partial
from pathlib import Path

from memsearch import eval as evalmod
from memsearch import index as indexmod
from memsearch import ollama, search, status
from memsearch.config import ConfigError, load_config
from memsearch.rename import rename_repo


def _default_embedder(cfg):
    return partial(ollama.embed, model=cfg.embed_model, base_url=cfg.ollama_url)


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="memsearch",
        description="Local hybrid RAG over session digests + durable docs")
    p.add_argument("--config", type=Path, default=None,
                   help="path to config.json (default: packaged)")
    sub = p.add_subparsers(dest="cmd", required=True)

    pi = sub.add_parser("index", help="incremental index (hash-diff)")
    pi.add_argument("--full", action="store_true",
                    help="rebuild from scratch (required after model change)")
    pi.add_argument("--limit", type=int, default=None,
                    help="cap transcripts processed this run")

    pq = sub.add_parser("query", help="hybrid search")
    pq.add_argument("text")
    pq.add_argument("--repo")
    pq.add_argument("--type", dest="rtype",
                    choices=["decision", "episodic", "doc"])
    pq.add_argument("--since", metavar="YYYY-MM-DD")
    pq.add_argument("-k", type=int, default=6)

    pr = sub.add_parser("rename", help="rename a repo (zero re-embed)")
    pr.add_argument("old")
    pr.add_argument("new")

    sub.add_parser("status", help="index health + revisit triggers")

    pe = sub.add_parser("eval-digests", help="systematic digest accuracy audit")
    pe.add_argument("--sample", type=int, default=12)
    pe.add_argument("--seed", type=int, default=17)
    return p


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        cfg = load_config(args.config)
        if args.cmd == "index":
            report = indexmod.run_index(cfg, full=args.full, limit=args.limit)
            print(f"processed={report['processed']} skipped={report['skipped']} "
                  f"chunks_added={report['chunks_added']} "
                  f"errors={len(report['errors'])}")
            for err in report["errors"]:
                print(f"  error: {err}", file=sys.stderr)
            return 0
        if args.cmd == "query":
            if not cfg.db_path.exists():
                print("no index yet — run `memsearch index`", file=sys.stderr)
                return 1
            results = search.search(
                cfg, args.text, k=args.k, repo=args.repo, rtype=args.rtype,
                since=args.since, embedder=_default_embedder(cfg))
            print(search.format_results(results))
            return 0
        if args.cmd == "rename":
            print(rename_repo(cfg, args.old, args.new))
            return 0
        if args.cmd == "status":
            print(status.status_report(cfg))
            return 0
        if args.cmd == "eval-digests":
            r = evalmod.audit_digests(cfg, sample=args.sample, seed=args.seed)
            print(f"sampled={r['sampled']} supported={r['supported']} "
                  f"unsupported={r['unsupported']}\nreport: {r['report_path']}")
            return 0 if not r["unsupported"] else 1
        raise AssertionError(f"unhandled cmd {args.cmd}")
    except (ConfigError, ollama.OllamaError) as e:
        print(f"memsearch: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
