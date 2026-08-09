window.TRACKER_DATA = {
  "version": 1,
  "tool": "task-tracker v0.4.1",
  "generatedAt": "2026-08-09T02:41:07Z",
  "repoUrls": {
    ".claude": "https://github.com/suyatdev/.claude",
    "memsearch": "https://github.com/suyatdev/memsearch",
    "cmux": "https://github.com/suyatdev/cmux"
  },
  "runs": [
    {
      "id": "guard-memsearch",
      "name": "guard + memsearch push",
      "dir": "~/dev/.claude",
      "analyzedAt": "2h ago",
      "features": [
        {
          "name": "memsearch-freshness",
          "meta": "0/4 merged",
          "tasks": [
            {
              "name": "Freshness scoring in ranker",
              "desc": "Half-life decay on chunk age, blended with BM25 score",
              "phase": "Implement", "pi": 1, "state": "In progress",
              "repo": "memsearch", "branch": "feat/freshness-ranker",
              "pr": "#142", "prState": "Draft", "prUrl": "https://github.com/suyatdev/memsearch/pull/142",
              "d": {
                "worktree": "~/wt/freshness-ranker", "diff": "+286 −41", "last": "20m ago",
                "commits": [
                  {"sha": "e7d21c4", "msg": "ranker: half-life decay term"},
                  {"sha": "2b9f0ae", "msg": "config: decay constant + unit tests"}
                ],
                "links": [{"t": "after — Digest re-index CLI #139", "kind": "after"}],
                "checklist": [
                  {"t": "Decay term behind flag", "done": true},
                  {"t": "Blend weights tuned on eval set", "done": false},
                  {"t": "Eval regression ≤ 1%", "done": false}
                ],
                "notes": "Blocked on real timestamps until #139 lands; using synthetic fixtures meanwhile."
              }
            },
            {
              "name": "Digest re-index CLI",
              "desc": "memsearch reindex --digest with dry-run plan",
              "phase": "Verify", "pi": 2, "state": "In review",
              "repo": "memsearch", "branch": "feat/digest-cli",
              "pr": "#139", "prState": "Open", "prUrl": "https://github.com/suyatdev/memsearch/pull/139",
              "d": {
                "worktree": "~/wt/memsearch-digest-cli", "diff": "+412 −86", "last": "2h ago",
                "commits": [
                  {"sha": "a3f19e2", "msg": "reindex: add --digest flag + dry-run plan"},
                  {"sha": "90c4d17", "msg": "db: expose last_indexed_at per chunk"},
                  {"sha": "5b82aa0", "msg": "tests: golden queries for stale digests"}
                ],
                "links": [{"t": "blocks — Freshness scoring in ranker", "kind": "blocks"}],
                "checklist": [
                  {"t": "Dry-run prints plan", "done": true},
                  {"t": "Re-index is idempotent", "done": true},
                  {"t": "Golden queries pass on CI", "done": false}
                ],
                "notes": "Land before the ranker so freshness reads real timestamps. One golden query is flaky on CI — see run 2214."
              }
            },
            {
              "name": "Stale-index nudge hook",
              "desc": "SessionStart nudge when index is older than digest",
              "phase": "Spec", "pi": 0, "state": "Not started",
              "repo": ".claude", "branch": "—", "pr": "—", "prState": "—",
              "d": {
                "worktree": "—", "diff": "", "last": "4d ago",
                "commits": [],
                "links": [],
                "checklist": [{"t": "Decision: SessionStart vs pre-search", "done": false}],
                "notes": "Waiting on open question Q1 — the trigger point decides the hook shape."
              }
            },
            {
              "name": "Freshness eval queries",
              "desc": "Measurement set for tuning the decay constant",
              "phase": "Verify", "pi": 2, "state": "In progress",
              "repo": "memsearch", "branch": "feat/freshness-evals", "pr": "—", "prState": "—",
              "d": {
                "worktree": "~/wt/freshness-evals", "diff": "+122 −8", "last": "1d ago",
                "commits": [{"sha": "4c81d02", "msg": "evals: 12 measurement queries"}],
                "links": [],
                "checklist": [
                  {"t": "Queries cover stale + fresh", "done": true},
                  {"t": "CI job wired", "done": false}
                ],
                "notes": "Measurement-only set; golden assertions come after decay tuning."
              }
            }
          ]
        },
        {
          "name": "phase-guard-hook",
          "meta": "1/3 merged",
          "tasks": [
            {
              "name": "Branch-scoped write permission",
              "desc": "Frontmatter phase gates writes per branch",
              "phase": "Review", "pi": 3, "state": "Blocked",
              "repo": ".claude", "branch": "feat/branch-write-perm",
              "pr": "#91", "prState": "Changes req.", "prUrl": "https://github.com/suyatdev/.claude/pull/91",
              "d": {
                "worktree": "~/wt/branch-write-perm", "diff": "+318 −64", "last": "3d ago",
                "commits": [
                  {"sha": "f41c09b", "msg": "hook: phase frontmatter → write permission map"},
                  {"sha": "7d2e881", "msg": "tests: deny cross-branch spec writes"}
                ],
                "links": [
                  {"t": "blocked by — reviewer changes on #91", "kind": "blockedBy"},
                  {"t": "after — Base pin resolution #96", "kind": "after"}
                ],
                "checklist": [
                  {"t": "Permission matrix in ADR", "done": false},
                  {"t": "Deny path has replay fixture", "done": true},
                  {"t": "Rebase onto main (behind 3)", "done": false}
                ],
                "notes": "Reviewer wants the phase→permission matrix split into its own ADR before approving. Rebase needed — main moved under it."
              }
            },
            {
              "name": "Guard replay harness",
              "desc": "Replays recorded sessions against the guard",
              "phase": "Implement", "pi": 1, "state": "Blocked",
              "repo": ".claude", "branch": "feat/guard-replay", "pr": "—", "prState": "—",
              "d": {
                "worktree": "~/wt/guard-replay", "diff": "+204 −0", "last": "5h ago",
                "commits": [{"sha": "91bd3e7", "msg": "harness: record/replay skeleton"}],
                "links": [
                  {"t": "blocked by — Base pin resolution #96", "kind": "blockedBy"},
                  {"t": "blocked by — Branch-scoped write permission #91", "kind": "blockedBy"}
                ],
                "checklist": [
                  {"t": "Replays 3 recorded sessions", "done": false},
                  {"t": "Differential mode proves difference", "done": false}
                ],
                "notes": "2 uncommitted files in the worktree. Waits for the #96 API; do not rebase before it lands."
              }
            },
            {
              "name": "Phase frontmatter parser",
              "desc": "Single source of phase truth for all hooks",
              "phase": "Ship", "pi": 4, "state": "Merged",
              "repo": ".claude", "branch": "feat/phase-frontmatter",
              "pr": "#87", "prState": "Merged", "prUrl": "https://github.com/suyatdev/.claude/pull/87",
              "d": {
                "worktree": "removed after merge", "diff": "", "last": "2w ago",
                "commits": [{"sha": "c3a9f11", "msg": "parser: phase → permission source"}],
                "links": [],
                "checklist": [
                  {"t": "Frontmatter is single source", "done": true},
                  {"t": "Hooks read parser, not regex", "done": true}
                ],
                "notes": "Merged in #87; worktree removed."
              }
            }
          ]
        },
        {
          "name": "replay-harness-base-pin",
          "meta": "0/1 · ready",
          "tasks": [
            {
              "name": "Base pin resolution",
              "desc": "Pin replay base to the recorded merge-base sha",
              "phase": "Verify", "pi": 2, "state": "In review",
              "repo": ".claude", "branch": "feat/replay-base-pin",
              "pr": "#96", "prState": "Approved", "prUrl": "https://github.com/suyatdev/.claude/pull/96",
              "d": {
                "worktree": "~/wt/replay-base-pin", "diff": "+156 −23", "last": "2h ago",
                "commits": [
                  {"sha": "8ee20b1", "msg": "pin: resolve recorded merge-base"},
                  {"sha": "03d571f", "msg": "tests: pin survives force-push"}
                ],
                "links": [
                  {"t": "blocks — Guard replay harness", "kind": "blocks"},
                  {"t": "blocks — Branch-scoped write permission #91", "kind": "blocks"}
                ],
                "checklist": [
                  {"t": "Approved by 2 reviewers", "done": true},
                  {"t": "CI green", "done": true},
                  {"t": "Squash + merge", "done": false}
                ],
                "notes": "Approved — merge first; everything in wave 2 rebases onto this."
              }
            }
          ]
        },
        {
          "name": "pane-split-policy",
          "meta": "0/2 · gated",
          "tasks": [
            {
              "name": "Three-lane governance config",
              "desc": "inline / panes max=N policy per session",
              "phase": "Implement", "pi": 1, "state": "In progress",
              "repo": "cmux", "branch": "feat/pane-split-policy",
              "pr": "#58", "prState": "Draft", "prUrl": "https://github.com/suyatdev/cmux/pull/58",
              "d": {
                "worktree": "~/wt/pane-split-policy", "diff": "+198 −57", "last": "6d ago",
                "commits": [{"sha": "77aa9c0", "msg": "policy: inline/panes max=N parsing"}],
                "links": [{"t": "gated by — cmux 0.9 version gate", "kind": "gated"}],
                "checklist": [
                  {"t": "Policy parser + defaults", "done": true},
                  {"t": "Dispatch honors lanes", "done": false}
                ],
                "notes": "Do not merge until cmux 0.9 tags — the version gate enforces this."
              }
            },
            {
              "name": "cmux exec adapter fixtures",
              "desc": "Replay fixtures for tab and layout probes",
              "phase": "Verify", "pi": 2, "state": "Stale",
              "repo": "cmux", "branch": "feat/exec-fixtures", "pr": "—", "prState": "—",
              "d": {
                "worktree": "~/wt/exec-fixtures", "diff": "+64 −12", "last": "6d ago",
                "commits": [{"sha": "5d0c2b8", "msg": "fixtures: tab probe recordings"}],
                "links": [{"t": "after — Three-lane governance config #58", "kind": "after"}],
                "checklist": [{"t": "Layout probe fixtures", "done": false}],
                "notes": "Re-record after governance lands; stale meanwhile."
              }
            }
          ]
        }
      ],
      "waves": [
        {"n": "1", "note": "ready now — approved / review open, CI green", "items": [
          {"t": "Base pin resolution", "pr": "#96", "prState": "Approved"},
          {"t": "Digest re-index CLI", "pr": "#139", "prState": "Open"}
        ]},
        {"n": "2", "note": "after wave 1 — unblocked by #96 landing", "items": [
          {"t": "Branch-scoped write permission", "pr": "#91", "prState": "Changes req."},
          {"t": "Freshness scoring in ranker", "pr": "#142", "prState": "Draft"}
        ]},
        {"n": "3", "note": "after #91 — rebases onto the pinned base", "items": [
          {"t": "Guard replay harness", "pr": "", "prState": ""}
        ]},
        {"n": "4", "note": "behind the cmux 0.9 gate — do not start merge", "items": [
          {"t": "Three-lane governance config", "pr": "#58", "prState": "Draft"},
          {"t": "cmux exec adapter fixtures", "pr": "", "prState": ""}
        ]}
      ],
      "constraints": [
        {"id": "C1", "title": "Base pin merges before any replay work", "pair": "#96 → #91 → guard-replay",
         "body": "Guard replay harness rebases onto the API introduced in replay-harness-base-pin (#96). Merging replay work first would re-record every fixture against an unpinned base — a silent falsification of the harness. Required order: #96, then branch-write-perm (#91), then guard-replay."},
        {"id": "C2", "title": "Digest CLI lands before the freshness ranker", "pair": "#139 → #142",
         "body": "The ranker reads last_indexed_at timestamps that the digest CLI writes. Merged in reverse, the ranker scores every chunk as maximally stale and the eval set is meaningless until a full re-index."},
        {"id": "C3", "title": "cmux merges frozen until the 0.9 version gate", "pair": "0.9 gate → #58 → fixtures",
         "body": "pane-split-policy targets the 0.9 layout API. The cmux-version-gate check blocks any merge to cmux until 0.9 tags; exec adapter fixtures re-record after governance lands."}
      ],
      "branches": [
        {"repo": ".claude", "branch": "main", "wt": "~/dev/.claude", "ahead": 0, "behind": 0, "dirty": false, "note": "clean", "tone": "ok", "last": "1h"},
        {"repo": ".claude", "branch": "feat/replay-base-pin", "wt": "~/wt/replay-base-pin", "ahead": 3, "behind": 0, "dirty": false, "note": "ready to merge", "tone": "ok", "last": "2h"},
        {"repo": ".claude", "branch": "feat/branch-write-perm", "wt": "~/wt/branch-write-perm", "ahead": 7, "behind": 3, "dirty": false, "note": "needs rebase", "tone": "warn", "last": "3d"},
        {"repo": ".claude", "branch": "feat/guard-replay", "wt": "~/wt/guard-replay", "ahead": 4, "behind": 0, "dirty": true, "note": "2 uncommitted", "tone": "bad", "last": "5h"},
        {"repo": "memsearch", "branch": "feat/digest-cli", "wt": "~/wt/memsearch-digest-cli", "ahead": 6, "behind": 0, "dirty": false, "note": "ready to merge", "tone": "ok", "last": "2h"},
        {"repo": "memsearch", "branch": "feat/freshness-ranker", "wt": "~/wt/freshness-ranker", "ahead": 12, "behind": 1, "dirty": true, "note": "WIP", "tone": "accent", "last": "20m"},
        {"repo": "memsearch", "branch": "feat/freshness-evals", "wt": "~/wt/freshness-evals", "ahead": 2, "behind": 0, "dirty": false, "note": "WIP", "tone": "accent", "last": "1d"},
        {"repo": "cmux", "branch": "feat/pane-split-policy", "wt": "~/wt/pane-split-policy", "ahead": 9, "behind": 5, "dirty": false, "note": "stale · 0.9 gate", "tone": "warn", "last": "6d"},
        {"repo": "cmux", "branch": "feat/exec-fixtures", "wt": "~/wt/exec-fixtures", "ahead": 2, "behind": 5, "dirty": false, "note": "stale", "tone": "warn", "last": "6d"}
      ],
      "graph": {
        "nodes": [
          {"id": "A", "label": "Base pin resolution", "sub": "#96 approved", "tone": "ok", "x": 8, "y": 16},
          {"id": "B", "label": "Digest re-index CLI", "sub": "#139 in review", "tone": "info", "x": 8, "y": 104},
          {"id": "C", "label": "cmux 0.9 gate", "sub": "external gate", "tone": "warn", "x": 8, "y": 192, "gate": true},
          {"id": "D", "label": "Branch write permission", "sub": "#91 changes req.", "tone": "warn", "x": 258, "y": 0},
          {"id": "E", "label": "Guard replay harness", "sub": "blocked", "tone": "bad", "x": 258, "y": 66},
          {"id": "F", "label": "Freshness ranker", "sub": "#142 draft", "tone": "accent", "x": 258, "y": 132},
          {"id": "G", "label": "Governance config", "sub": "#58 draft", "tone": "accent", "x": 258, "y": 198},
          {"id": "H", "label": "exec fixtures", "sub": "stale", "tone": "neutral", "x": 508, "y": 198}
        ],
        "edges": [["A","D"],["D","E"],["B","F"],["C","G"],["G","H"]]
      },
      "kanban": [
        {"title": "Up next", "tone": "accent", "items": [
          {"t": "Stale-index nudge hook", "m": ".claude · spec"},
          {"t": "Rebase branch-write-perm onto main", "m": ".claude · ↓3"},
          {"t": "Fix flaky golden query", "m": "memsearch · CI 2214"}
        ]},
        {"title": "In progress", "tone": "info", "items": [
          {"t": "Freshness scoring in ranker", "m": "#142 · memsearch"},
          {"t": "Three-lane governance config", "m": "#58 · cmux"},
          {"t": "Freshness eval queries", "m": "memsearch"}
        ]},
        {"title": "Blocked", "tone": "bad", "items": [
          {"t": "Guard replay harness", "m": "waits on #96 → #91"},
          {"t": "Branch-scoped write permission", "m": "changes requested"}
        ]},
        {"title": "In review", "tone": "ok", "items": [
          {"t": "Base pin resolution", "m": "#96 approved — merge it"},
          {"t": "Digest re-index CLI", "m": "#139 open · 1 flaky check"}
        ]}
      ],
      "questions": [
        {"id": "q1", "q": "Nudge hook: fire on SessionStart or pre-search?", "ctx": "SessionStart is cheap but stale by mid-session; pre-search adds ~80ms to every query.", "resolved": false},
        {"id": "q2", "q": "Split the #91 permission matrix into its own ADR?", "ctx": "Reviewer wants the phase→permission table versioned separately from the hook code.", "resolved": false},
        {"id": "q3", "q": "Freeze cmux work until 0.9 tags?", "ctx": "Resolved yes — enforced by the cmux-version-gate check.", "resolved": true}
      ]
    },
    {
      "id": "pane-orchestration-v2",
      "name": "pane orchestration v2",
      "dir": "~/dev/cmux",
      "analyzedAt": "3d ago",
      "features": [
        {
          "name": "pane-orchestration",
          "meta": "0/3 merged",
          "tasks": [
            {
              "name": "Dispatch pane agent rewrite",
              "desc": "Three-lane routing: Explore/Plan in-process, judges paned",
              "phase": "Implement", "pi": 1, "state": "In progress",
              "repo": "cmux", "branch": "feat/dispatch-rewrite",
              "pr": "#61", "prState": "Draft", "prUrl": "https://github.com/suyatdev/cmux/pull/61",
              "d": {
                "worktree": "~/wt/dispatch-rewrite", "diff": "+342 −198", "last": "3d ago",
                "commits": [{"sha": "aa1f0d3", "msg": "dispatch: three-lane routing core"}],
                "links": [{"t": "after — Result-file contract #59", "kind": "after"}],
                "checklist": [
                  {"t": "Explore/Plan in-process", "done": true},
                  {"t": "Judges always paned", "done": false}
                ],
                "notes": "Routing core in; judge lane pending the contract."
              }
            },
            {
              "name": "Result-file contract",
              "desc": "Versioned result file schema + waiter",
              "phase": "Verify", "pi": 2, "state": "In review",
              "repo": "cmux", "branch": "feat/result-contract",
              "pr": "#59", "prState": "Open", "prUrl": "https://github.com/suyatdev/cmux/pull/59",
              "d": {
                "worktree": "~/wt/result-contract", "diff": "+88 −30", "last": "4d ago",
                "commits": [{"sha": "c91e2f0", "msg": "contract: result file schema + waiter"}],
                "links": [{"t": "blocks — Dispatch pane agent rewrite", "kind": "blocks"}],
                "checklist": [
                  {"t": "Schema versioned", "done": true},
                  {"t": "Timeout fallback documented", "done": false}
                ],
                "notes": "One naming question open in review."
              }
            },
            {
              "name": "Wait timeout fallback rules",
              "desc": "What happens when a paned agent never writes its result",
              "phase": "Spec", "pi": 0, "state": "Not started",
              "repo": "cmux", "branch": "—", "pr": "—", "prState": "—",
              "d": {
                "worktree": "—", "diff": "", "last": "5d ago",
                "commits": [], "links": [],
                "checklist": [{"t": "Spec after contract settles", "done": false}],
                "notes": "Spec next after the contract review settles."
              }
            }
          ]
        },
        {
          "name": "cmux-version-gate",
          "meta": "1/1 merged",
          "tasks": [
            {
              "name": "0.9 gate check in merge-guard",
              "desc": "Blocks cmux merges until 0.9 tags",
              "phase": "Ship", "pi": 4, "state": "Merged",
              "repo": ".claude", "branch": "feat/cmux-version-gate",
              "pr": "#55", "prState": "Merged", "prUrl": "https://github.com/suyatdev/.claude/pull/55",
              "d": {
                "worktree": "removed after merge", "diff": "", "last": "2w ago",
                "commits": [{"sha": "b02d9c7", "msg": "merge-guard: cmux version gate"}],
                "links": [],
                "checklist": [{"t": "Gate blocks pre-0.9", "done": true}],
                "notes": "Landed; blocks cmux merges pre-0.9."
              }
            }
          ]
        }
      ],
      "waves": [
        {"n": "1", "note": "ready after review — schema is the dependency", "items": [
          {"t": "Result-file contract", "pr": "#59", "prState": "Open"}
        ]},
        {"n": "2", "note": "consumes the versioned schema", "items": [
          {"t": "Dispatch pane agent rewrite", "pr": "#61", "prState": "Draft"}
        ]},
        {"n": "3", "note": "spec only — no branch yet", "items": [
          {"t": "Wait timeout fallback rules", "pr": "", "prState": ""}
        ]}
      ],
      "constraints": [
        {"id": "C1", "title": "Contract merges before the dispatch rewrite", "pair": "#59 → #61",
         "body": "The rewrite consumes the versioned result-file schema; merging #61 first ships an unversioned reader that every paned agent would then depend on."}
      ],
      "branches": [
        {"repo": "cmux", "branch": "main", "wt": "~/dev/cmux", "ahead": 0, "behind": 0, "dirty": false, "note": "clean", "tone": "ok", "last": "1h"},
        {"repo": "cmux", "branch": "feat/dispatch-rewrite", "wt": "~/wt/dispatch-rewrite", "ahead": 11, "behind": 0, "dirty": true, "note": "WIP", "tone": "accent", "last": "3d"},
        {"repo": "cmux", "branch": "feat/result-contract", "wt": "~/wt/result-contract", "ahead": 4, "behind": 0, "dirty": false, "note": "ready to merge", "tone": "ok", "last": "4d"}
      ],
      "graph": {
        "nodes": [
          {"id": "A", "label": "Result-file contract", "sub": "#59 in review", "tone": "info", "x": 8, "y": 60},
          {"id": "B", "label": "Dispatch rewrite", "sub": "#61 draft", "tone": "accent", "x": 258, "y": 60},
          {"id": "C", "label": "Timeout fallback rules", "sub": "spec", "tone": "neutral", "x": 508, "y": 60}
        ],
        "edges": [["A","B"],["B","C"]]
      },
      "kanban": [
        {"title": "Up next", "tone": "accent", "items": [{"t": "Wait timeout fallback spec", "m": "cmux"}]},
        {"title": "In progress", "tone": "info", "items": [{"t": "Dispatch pane agent rewrite", "m": "#61 · cmux"}]},
        {"title": "Blocked", "tone": "bad", "items": []},
        {"title": "In review", "tone": "ok", "items": [{"t": "Result-file contract", "m": "#59 open"}]}
      ],
      "questions": [
        {"id": "q1", "q": "Result path: per-agent dir or flat files?", "ctx": "Open on the #59 review thread — flat is simpler, per-agent survives restarts.", "resolved": false},
        {"id": "q2", "q": "Adopt handoff-wrapper for paned judges?", "ctx": "Resolved yes — wrapper ships with the dispatch rewrite.", "resolved": true}
      ]
    },
    {
      "id": "statusline-wrap",
      "name": "statusline wrap",
      "dir": "~/dev/.claude",
      "analyzedAt": "1w ago",
      "features": [
        {
          "name": "statusline-wrap-worktree",
          "meta": "2/2 merged",
          "tasks": [
            {
              "name": "Multi-row wrap layout",
              "desc": "Status line may span multiple rows (ADR 0018)",
              "phase": "Ship", "pi": 4, "state": "Merged",
              "repo": ".claude", "branch": "feat/statusline-wrap",
              "pr": "#78", "prState": "Merged", "prUrl": "https://github.com/suyatdev/.claude/pull/78",
              "d": {
                "worktree": "removed after merge", "diff": "", "last": "1w ago",
                "commits": [{"sha": "d4e8a10", "msg": "statusline: wrap segments across rows"}],
                "links": [],
                "checklist": [{"t": "ADR 0018 recorded", "done": true}],
                "notes": "Shipped — see ADR 0018, the status line may span multiple rows."
              }
            },
            {
              "name": "Worktree segment truncation",
              "desc": "Middle-truncate long worktree paths in the segment",
              "phase": "Ship", "pi": 4, "state": "Merged",
              "repo": ".claude", "branch": "feat/statusline-wrap",
              "pr": "#78", "prState": "Merged", "prUrl": "https://github.com/suyatdev/.claude/pull/78",
              "d": {
                "worktree": "removed after merge", "diff": "", "last": "1w ago",
                "commits": [{"sha": "9f11c3b", "msg": "statusline: middle-truncate worktree paths"}],
                "links": [],
                "checklist": [{"t": "Truncation keeps repo + leaf", "done": true}],
                "notes": "Shipped with the wrap PR."
              }
            }
          ]
        }
      ],
      "waves": [
        {"n": "1", "note": "complete — both merged in #78", "items": [
          {"t": "Multi-row wrap layout", "pr": "#78", "prState": "Merged"},
          {"t": "Worktree segment truncation", "pr": "#78", "prState": "Merged"}
        ]}
      ],
      "constraints": [],
      "branches": [
        {"repo": ".claude", "branch": "main", "wt": "~/dev/.claude", "ahead": 0, "behind": 0, "dirty": false, "note": "clean", "tone": "ok", "last": "1h"}
      ],
      "graph": {
        "nodes": [
          {"id": "A", "label": "Multi-row wrap layout", "sub": "#78 merged", "tone": "ok", "x": 8, "y": 60},
          {"id": "B", "label": "Worktree truncation", "sub": "#78 merged", "tone": "ok", "x": 258, "y": 60}
        ],
        "edges": [["A","B"]]
      },
      "kanban": [],
      "questions": [
        {"id": "q1", "q": "Wrap threshold: cap at 2 rows?", "ctx": "Resolved yes — 2 rows max, then truncate segments.", "resolved": true}
      ]
    }
  ]
};
