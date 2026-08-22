window.TRACKER_DATA = {
  "version": 1,
  "tool": "task-tracker v0.4.1",
  "generatedAt": "2026-08-20T03:07:28Z",
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
              "phase": "Implement",
              "pi": 1,
              "state": "In progress",
              "repo": "memsearch",
              "branch": "feat/freshness-ranker",
              "pr": "#142",
              "prState": "Draft",
              "prUrl": "https://github.com/suyatdev/memsearch/pull/142",
              "d": {
                "worktree": "~/wt/freshness-ranker",
                "diff": "+286 \u221241",
                "last": "20m ago",
                "commits": [
                  {
                    "sha": "e7d21c4",
                    "msg": "ranker: half-life decay term"
                  },
                  {
                    "sha": "2b9f0ae",
                    "msg": "config: decay constant + unit tests"
                  }
                ],
                "links": [
                  {
                    "t": "after \u2014 Digest re-index CLI #139",
                    "kind": "after"
                  }
                ],
                "checklist": [
                  {
                    "t": "Decay term behind flag",
                    "done": true
                  },
                  {
                    "t": "Blend weights tuned on eval set",
                    "done": false
                  },
                  {
                    "t": "Eval regression \u2264 1%",
                    "done": false
                  }
                ],
                "notes": "Blocked on real timestamps until #139 lands; using synthetic fixtures meanwhile."
              }
            },
            {
              "name": "Digest re-index CLI",
              "desc": "memsearch reindex --digest with dry-run plan",
              "phase": "Verify",
              "pi": 2,
              "state": "In review",
              "repo": "memsearch",
              "branch": "feat/digest-cli",
              "pr": "#139",
              "prState": "Open",
              "prUrl": "https://github.com/suyatdev/memsearch/pull/139",
              "d": {
                "worktree": "~/wt/memsearch-digest-cli",
                "diff": "+412 \u221286",
                "last": "2h ago",
                "commits": [
                  {
                    "sha": "a3f19e2",
                    "msg": "reindex: add --digest flag + dry-run plan"
                  },
                  {
                    "sha": "90c4d17",
                    "msg": "db: expose last_indexed_at per chunk"
                  },
                  {
                    "sha": "5b82aa0",
                    "msg": "tests: golden queries for stale digests"
                  }
                ],
                "links": [
                  {
                    "t": "blocks \u2014 Freshness scoring in ranker",
                    "kind": "blocks"
                  }
                ],
                "checklist": [
                  {
                    "t": "Dry-run prints plan",
                    "done": true
                  },
                  {
                    "t": "Re-index is idempotent",
                    "done": true
                  },
                  {
                    "t": "Golden queries pass on CI",
                    "done": false
                  }
                ],
                "notes": "Land before the ranker so freshness reads real timestamps. One golden query is flaky on CI \u2014 see run 2214."
              }
            },
            {
              "name": "Stale-index nudge hook",
              "desc": "SessionStart nudge when index is older than digest",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": ".claude",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "4d ago",
                "commits": [],
                "links": [],
                "checklist": [
                  {
                    "t": "Decision: SessionStart vs pre-search",
                    "done": false
                  }
                ],
                "notes": "Waiting on open question Q1 \u2014 the trigger point decides the hook shape."
              }
            },
            {
              "name": "Freshness eval queries",
              "desc": "Measurement set for tuning the decay constant",
              "phase": "Verify",
              "pi": 2,
              "state": "In progress",
              "repo": "memsearch",
              "branch": "feat/freshness-evals",
              "pr": "\u2014",
              "prState": "\u2014",
              "d": {
                "worktree": "~/wt/freshness-evals",
                "diff": "+122 \u22128",
                "last": "1d ago",
                "commits": [
                  {
                    "sha": "4c81d02",
                    "msg": "evals: 12 measurement queries"
                  }
                ],
                "links": [],
                "checklist": [
                  {
                    "t": "Queries cover stale + fresh",
                    "done": true
                  },
                  {
                    "t": "CI job wired",
                    "done": false
                  }
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
              "phase": "Review",
              "pi": 3,
              "state": "Blocked",
              "repo": ".claude",
              "branch": "feat/branch-write-perm",
              "pr": "#91",
              "prState": "Changes req.",
              "prUrl": "https://github.com/suyatdev/.claude/pull/91",
              "d": {
                "worktree": "~/wt/branch-write-perm",
                "diff": "+318 \u221264",
                "last": "3d ago",
                "commits": [
                  {
                    "sha": "f41c09b",
                    "msg": "hook: phase frontmatter \u2192 write permission map"
                  },
                  {
                    "sha": "7d2e881",
                    "msg": "tests: deny cross-branch spec writes"
                  }
                ],
                "links": [
                  {
                    "t": "blocked by \u2014 reviewer changes on #91",
                    "kind": "blockedBy"
                  },
                  {
                    "t": "after \u2014 Base pin resolution #96",
                    "kind": "after"
                  }
                ],
                "checklist": [
                  {
                    "t": "Permission matrix in ADR",
                    "done": false
                  },
                  {
                    "t": "Deny path has replay fixture",
                    "done": true
                  },
                  {
                    "t": "Rebase onto main (behind 3)",
                    "done": false
                  }
                ],
                "notes": "Reviewer wants the phase\u2192permission matrix split into its own ADR before approving. Rebase needed \u2014 main moved under it."
              }
            },
            {
              "name": "Guard replay harness",
              "desc": "Replays recorded sessions against the guard",
              "phase": "Implement",
              "pi": 1,
              "state": "Blocked",
              "repo": ".claude",
              "branch": "feat/guard-replay",
              "pr": "\u2014",
              "prState": "\u2014",
              "d": {
                "worktree": "~/wt/guard-replay",
                "diff": "+204 \u22120",
                "last": "5h ago",
                "commits": [
                  {
                    "sha": "91bd3e7",
                    "msg": "harness: record/replay skeleton"
                  }
                ],
                "links": [
                  {
                    "t": "blocked by \u2014 Base pin resolution #96",
                    "kind": "blockedBy"
                  },
                  {
                    "t": "blocked by \u2014 Branch-scoped write permission #91",
                    "kind": "blockedBy"
                  }
                ],
                "checklist": [
                  {
                    "t": "Replays 3 recorded sessions",
                    "done": false
                  },
                  {
                    "t": "Differential mode proves difference",
                    "done": false
                  }
                ],
                "notes": "2 uncommitted files in the worktree. Waits for the #96 API; do not rebase before it lands."
              }
            },
            {
              "name": "Phase frontmatter parser",
              "desc": "Single source of phase truth for all hooks",
              "phase": "Ship",
              "pi": 4,
              "state": "Merged",
              "repo": ".claude",
              "branch": "feat/phase-frontmatter",
              "pr": "#87",
              "prState": "Merged",
              "prUrl": "https://github.com/suyatdev/.claude/pull/87",
              "d": {
                "worktree": "removed after merge",
                "diff": "",
                "last": "2w ago",
                "commits": [
                  {
                    "sha": "c3a9f11",
                    "msg": "parser: phase \u2192 permission source"
                  }
                ],
                "links": [],
                "checklist": [
                  {
                    "t": "Frontmatter is single source",
                    "done": true
                  },
                  {
                    "t": "Hooks read parser, not regex",
                    "done": true
                  }
                ],
                "notes": "Merged in #87; worktree removed."
              }
            }
          ]
        },
        {
          "name": "replay-harness-base-pin",
          "meta": "0/1 \u00b7 ready",
          "tasks": [
            {
              "name": "Base pin resolution",
              "desc": "Pin replay base to the recorded merge-base sha",
              "phase": "Verify",
              "pi": 2,
              "state": "In review",
              "repo": ".claude",
              "branch": "feat/replay-base-pin",
              "pr": "#96",
              "prState": "Approved",
              "prUrl": "https://github.com/suyatdev/.claude/pull/96",
              "d": {
                "worktree": "~/wt/replay-base-pin",
                "diff": "+156 \u221223",
                "last": "2h ago",
                "commits": [
                  {
                    "sha": "8ee20b1",
                    "msg": "pin: resolve recorded merge-base"
                  },
                  {
                    "sha": "03d571f",
                    "msg": "tests: pin survives force-push"
                  }
                ],
                "links": [
                  {
                    "t": "blocks \u2014 Guard replay harness",
                    "kind": "blocks"
                  },
                  {
                    "t": "blocks \u2014 Branch-scoped write permission #91",
                    "kind": "blocks"
                  }
                ],
                "checklist": [
                  {
                    "t": "Approved by 2 reviewers",
                    "done": true
                  },
                  {
                    "t": "CI green",
                    "done": true
                  },
                  {
                    "t": "Squash + merge",
                    "done": false
                  }
                ],
                "notes": "Approved \u2014 merge first; everything in wave 2 rebases onto this."
              }
            }
          ]
        },
        {
          "name": "pane-split-policy",
          "meta": "0/2 \u00b7 gated",
          "tasks": [
            {
              "name": "Three-lane governance config",
              "desc": "inline / panes max=N policy per session",
              "phase": "Implement",
              "pi": 1,
              "state": "In progress",
              "repo": "cmux",
              "branch": "feat/pane-split-policy",
              "pr": "#58",
              "prState": "Draft",
              "prUrl": "https://github.com/suyatdev/cmux/pull/58",
              "d": {
                "worktree": "~/wt/pane-split-policy",
                "diff": "+198 \u221257",
                "last": "6d ago",
                "commits": [
                  {
                    "sha": "77aa9c0",
                    "msg": "policy: inline/panes max=N parsing"
                  }
                ],
                "links": [
                  {
                    "t": "gated by \u2014 cmux 0.9 version gate",
                    "kind": "gated"
                  }
                ],
                "checklist": [
                  {
                    "t": "Policy parser + defaults",
                    "done": true
                  },
                  {
                    "t": "Dispatch honors lanes",
                    "done": false
                  }
                ],
                "notes": "Do not merge until cmux 0.9 tags \u2014 the version gate enforces this."
              }
            },
            {
              "name": "cmux exec adapter fixtures",
              "desc": "Replay fixtures for tab and layout probes",
              "phase": "Verify",
              "pi": 2,
              "state": "Stale",
              "repo": "cmux",
              "branch": "feat/exec-fixtures",
              "pr": "\u2014",
              "prState": "\u2014",
              "d": {
                "worktree": "~/wt/exec-fixtures",
                "diff": "+64 \u221212",
                "last": "6d ago",
                "commits": [
                  {
                    "sha": "5d0c2b8",
                    "msg": "fixtures: tab probe recordings"
                  }
                ],
                "links": [
                  {
                    "t": "after \u2014 Three-lane governance config #58",
                    "kind": "after"
                  }
                ],
                "checklist": [
                  {
                    "t": "Layout probe fixtures",
                    "done": false
                  }
                ],
                "notes": "Re-record after governance lands; stale meanwhile."
              }
            }
          ]
        }
      ],
      "waves": [
        {
          "n": "1",
          "note": "ready now \u2014 approved / review open, CI green",
          "items": [
            {
              "t": "Base pin resolution",
              "pr": "#96",
              "prState": "Approved"
            },
            {
              "t": "Digest re-index CLI",
              "pr": "#139",
              "prState": "Open"
            }
          ]
        },
        {
          "n": "2",
          "note": "after wave 1 \u2014 unblocked by #96 landing",
          "items": [
            {
              "t": "Branch-scoped write permission",
              "pr": "#91",
              "prState": "Changes req."
            },
            {
              "t": "Freshness scoring in ranker",
              "pr": "#142",
              "prState": "Draft"
            }
          ]
        },
        {
          "n": "3",
          "note": "after #91 \u2014 rebases onto the pinned base",
          "items": [
            {
              "t": "Guard replay harness",
              "pr": "",
              "prState": ""
            }
          ]
        },
        {
          "n": "4",
          "note": "behind the cmux 0.9 gate \u2014 do not start merge",
          "items": [
            {
              "t": "Three-lane governance config",
              "pr": "#58",
              "prState": "Draft"
            },
            {
              "t": "cmux exec adapter fixtures",
              "pr": "",
              "prState": ""
            }
          ]
        }
      ],
      "constraints": [
        {
          "id": "C1",
          "title": "Base pin merges before any replay work",
          "pair": "#96 \u2192 #91 \u2192 guard-replay",
          "body": "Guard replay harness rebases onto the API introduced in replay-harness-base-pin (#96). Merging replay work first would re-record every fixture against an unpinned base \u2014 a silent falsification of the harness. Required order: #96, then branch-write-perm (#91), then guard-replay."
        },
        {
          "id": "C2",
          "title": "Digest CLI lands before the freshness ranker",
          "pair": "#139 \u2192 #142",
          "body": "The ranker reads last_indexed_at timestamps that the digest CLI writes. Merged in reverse, the ranker scores every chunk as maximally stale and the eval set is meaningless until a full re-index."
        },
        {
          "id": "C3",
          "title": "cmux merges frozen until the 0.9 version gate",
          "pair": "0.9 gate \u2192 #58 \u2192 fixtures",
          "body": "pane-split-policy targets the 0.9 layout API. The cmux-version-gate check blocks any merge to cmux until 0.9 tags; exec adapter fixtures re-record after governance lands."
        }
      ],
      "branches": [
        {
          "repo": ".claude",
          "branch": "main",
          "wt": "~/dev/.claude",
          "ahead": 0,
          "behind": 0,
          "dirty": false,
          "note": "clean",
          "tone": "ok",
          "last": "1h"
        },
        {
          "repo": ".claude",
          "branch": "feat/replay-base-pin",
          "wt": "~/wt/replay-base-pin",
          "ahead": 3,
          "behind": 0,
          "dirty": false,
          "note": "ready to merge",
          "tone": "ok",
          "last": "2h"
        },
        {
          "repo": ".claude",
          "branch": "feat/branch-write-perm",
          "wt": "~/wt/branch-write-perm",
          "ahead": 7,
          "behind": 3,
          "dirty": false,
          "note": "needs rebase",
          "tone": "warn",
          "last": "3d"
        },
        {
          "repo": ".claude",
          "branch": "feat/guard-replay",
          "wt": "~/wt/guard-replay",
          "ahead": 4,
          "behind": 0,
          "dirty": true,
          "note": "2 uncommitted",
          "tone": "bad",
          "last": "5h"
        },
        {
          "repo": "memsearch",
          "branch": "feat/digest-cli",
          "wt": "~/wt/memsearch-digest-cli",
          "ahead": 6,
          "behind": 0,
          "dirty": false,
          "note": "ready to merge",
          "tone": "ok",
          "last": "2h"
        },
        {
          "repo": "memsearch",
          "branch": "feat/freshness-ranker",
          "wt": "~/wt/freshness-ranker",
          "ahead": 12,
          "behind": 1,
          "dirty": true,
          "note": "WIP",
          "tone": "accent",
          "last": "20m"
        },
        {
          "repo": "memsearch",
          "branch": "feat/freshness-evals",
          "wt": "~/wt/freshness-evals",
          "ahead": 2,
          "behind": 0,
          "dirty": false,
          "note": "WIP",
          "tone": "accent",
          "last": "1d"
        },
        {
          "repo": "cmux",
          "branch": "feat/pane-split-policy",
          "wt": "~/wt/pane-split-policy",
          "ahead": 9,
          "behind": 5,
          "dirty": false,
          "note": "stale \u00b7 0.9 gate",
          "tone": "warn",
          "last": "6d"
        },
        {
          "repo": "cmux",
          "branch": "feat/exec-fixtures",
          "wt": "~/wt/exec-fixtures",
          "ahead": 2,
          "behind": 5,
          "dirty": false,
          "note": "stale",
          "tone": "warn",
          "last": "6d"
        }
      ],
      "graph": {
        "nodes": [
          {
            "id": "A",
            "label": "Base pin resolution",
            "sub": "#96 approved",
            "tone": "ok",
            "x": 8,
            "y": 16
          },
          {
            "id": "B",
            "label": "Digest re-index CLI",
            "sub": "#139 in review",
            "tone": "info",
            "x": 8,
            "y": 104
          },
          {
            "id": "C",
            "label": "cmux 0.9 gate",
            "sub": "external gate",
            "tone": "warn",
            "x": 8,
            "y": 192,
            "gate": true
          },
          {
            "id": "D",
            "label": "Branch write permission",
            "sub": "#91 changes req.",
            "tone": "warn",
            "x": 258,
            "y": 0
          },
          {
            "id": "E",
            "label": "Guard replay harness",
            "sub": "blocked",
            "tone": "bad",
            "x": 258,
            "y": 66
          },
          {
            "id": "F",
            "label": "Freshness ranker",
            "sub": "#142 draft",
            "tone": "accent",
            "x": 258,
            "y": 132
          },
          {
            "id": "G",
            "label": "Governance config",
            "sub": "#58 draft",
            "tone": "accent",
            "x": 258,
            "y": 198
          },
          {
            "id": "H",
            "label": "exec fixtures",
            "sub": "stale",
            "tone": "neutral",
            "x": 508,
            "y": 198
          }
        ],
        "edges": [
          [
            "A",
            "D"
          ],
          [
            "D",
            "E"
          ],
          [
            "B",
            "F"
          ],
          [
            "C",
            "G"
          ],
          [
            "G",
            "H"
          ]
        ]
      },
      "kanban": [
        {
          "title": "Up next",
          "tone": "accent",
          "items": [
            {
              "t": "Stale-index nudge hook",
              "m": ".claude \u00b7 spec"
            },
            {
              "t": "Rebase branch-write-perm onto main",
              "m": ".claude \u00b7 \u21933"
            },
            {
              "t": "Fix flaky golden query",
              "m": "memsearch \u00b7 CI 2214"
            }
          ]
        },
        {
          "title": "In progress",
          "tone": "info",
          "items": [
            {
              "t": "Freshness scoring in ranker",
              "m": "#142 \u00b7 memsearch"
            },
            {
              "t": "Three-lane governance config",
              "m": "#58 \u00b7 cmux"
            },
            {
              "t": "Freshness eval queries",
              "m": "memsearch"
            }
          ]
        },
        {
          "title": "Blocked",
          "tone": "bad",
          "items": [
            {
              "t": "Guard replay harness",
              "m": "waits on #96 \u2192 #91"
            },
            {
              "t": "Branch-scoped write permission",
              "m": "changes requested"
            }
          ]
        },
        {
          "title": "In review",
          "tone": "ok",
          "items": [
            {
              "t": "Base pin resolution",
              "m": "#96 approved \u2014 merge it"
            },
            {
              "t": "Digest re-index CLI",
              "m": "#139 open \u00b7 1 flaky check"
            }
          ]
        }
      ],
      "questions": [
        {
          "id": "q1",
          "q": "Nudge hook: fire on SessionStart or pre-search?",
          "ctx": "SessionStart is cheap but stale by mid-session; pre-search adds ~80ms to every query.",
          "resolved": false
        },
        {
          "id": "q2",
          "q": "Split the #91 permission matrix into its own ADR?",
          "ctx": "Reviewer wants the phase\u2192permission table versioned separately from the hook code.",
          "resolved": false
        },
        {
          "id": "q3",
          "q": "Freeze cmux work until 0.9 tags?",
          "ctx": "Resolved yes \u2014 enforced by the cmux-version-gate check.",
          "resolved": true
        }
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
              "phase": "Implement",
              "pi": 1,
              "state": "In progress",
              "repo": "cmux",
              "branch": "feat/dispatch-rewrite",
              "pr": "#61",
              "prState": "Draft",
              "prUrl": "https://github.com/suyatdev/cmux/pull/61",
              "d": {
                "worktree": "~/wt/dispatch-rewrite",
                "diff": "+342 \u2212198",
                "last": "3d ago",
                "commits": [
                  {
                    "sha": "aa1f0d3",
                    "msg": "dispatch: three-lane routing core"
                  }
                ],
                "links": [
                  {
                    "t": "after \u2014 Result-file contract #59",
                    "kind": "after"
                  }
                ],
                "checklist": [
                  {
                    "t": "Explore/Plan in-process",
                    "done": true
                  },
                  {
                    "t": "Judges always paned",
                    "done": false
                  }
                ],
                "notes": "Routing core in; judge lane pending the contract."
              }
            },
            {
              "name": "Result-file contract",
              "desc": "Versioned result file schema + waiter",
              "phase": "Verify",
              "pi": 2,
              "state": "In review",
              "repo": "cmux",
              "branch": "feat/result-contract",
              "pr": "#59",
              "prState": "Open",
              "prUrl": "https://github.com/suyatdev/cmux/pull/59",
              "d": {
                "worktree": "~/wt/result-contract",
                "diff": "+88 \u221230",
                "last": "4d ago",
                "commits": [
                  {
                    "sha": "c91e2f0",
                    "msg": "contract: result file schema + waiter"
                  }
                ],
                "links": [
                  {
                    "t": "blocks \u2014 Dispatch pane agent rewrite",
                    "kind": "blocks"
                  }
                ],
                "checklist": [
                  {
                    "t": "Schema versioned",
                    "done": true
                  },
                  {
                    "t": "Timeout fallback documented",
                    "done": false
                  }
                ],
                "notes": "One naming question open in review."
              }
            },
            {
              "name": "Wait timeout fallback rules",
              "desc": "What happens when a paned agent never writes its result",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "cmux",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "5d ago",
                "commits": [],
                "links": [],
                "checklist": [
                  {
                    "t": "Spec after contract settles",
                    "done": false
                  }
                ],
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
              "phase": "Ship",
              "pi": 4,
              "state": "Merged",
              "repo": ".claude",
              "branch": "feat/cmux-version-gate",
              "pr": "#55",
              "prState": "Merged",
              "prUrl": "https://github.com/suyatdev/.claude/pull/55",
              "d": {
                "worktree": "removed after merge",
                "diff": "",
                "last": "2w ago",
                "commits": [
                  {
                    "sha": "b02d9c7",
                    "msg": "merge-guard: cmux version gate"
                  }
                ],
                "links": [],
                "checklist": [
                  {
                    "t": "Gate blocks pre-0.9",
                    "done": true
                  }
                ],
                "notes": "Landed; blocks cmux merges pre-0.9."
              }
            }
          ]
        }
      ],
      "waves": [
        {
          "n": "1",
          "note": "ready after review \u2014 schema is the dependency",
          "items": [
            {
              "t": "Result-file contract",
              "pr": "#59",
              "prState": "Open"
            }
          ]
        },
        {
          "n": "2",
          "note": "consumes the versioned schema",
          "items": [
            {
              "t": "Dispatch pane agent rewrite",
              "pr": "#61",
              "prState": "Draft"
            }
          ]
        },
        {
          "n": "3",
          "note": "spec only \u2014 no branch yet",
          "items": [
            {
              "t": "Wait timeout fallback rules",
              "pr": "",
              "prState": ""
            }
          ]
        }
      ],
      "constraints": [
        {
          "id": "C1",
          "title": "Contract merges before the dispatch rewrite",
          "pair": "#59 \u2192 #61",
          "body": "The rewrite consumes the versioned result-file schema; merging #61 first ships an unversioned reader that every paned agent would then depend on."
        }
      ],
      "branches": [
        {
          "repo": "cmux",
          "branch": "main",
          "wt": "~/dev/cmux",
          "ahead": 0,
          "behind": 0,
          "dirty": false,
          "note": "clean",
          "tone": "ok",
          "last": "1h"
        },
        {
          "repo": "cmux",
          "branch": "feat/dispatch-rewrite",
          "wt": "~/wt/dispatch-rewrite",
          "ahead": 11,
          "behind": 0,
          "dirty": true,
          "note": "WIP",
          "tone": "accent",
          "last": "3d"
        },
        {
          "repo": "cmux",
          "branch": "feat/result-contract",
          "wt": "~/wt/result-contract",
          "ahead": 4,
          "behind": 0,
          "dirty": false,
          "note": "ready to merge",
          "tone": "ok",
          "last": "4d"
        }
      ],
      "graph": {
        "nodes": [
          {
            "id": "A",
            "label": "Result-file contract",
            "sub": "#59 in review",
            "tone": "info",
            "x": 8,
            "y": 60
          },
          {
            "id": "B",
            "label": "Dispatch rewrite",
            "sub": "#61 draft",
            "tone": "accent",
            "x": 258,
            "y": 60
          },
          {
            "id": "C",
            "label": "Timeout fallback rules",
            "sub": "spec",
            "tone": "neutral",
            "x": 508,
            "y": 60
          }
        ],
        "edges": [
          [
            "A",
            "B"
          ],
          [
            "B",
            "C"
          ]
        ]
      },
      "kanban": [
        {
          "title": "Up next",
          "tone": "accent",
          "items": [
            {
              "t": "Wait timeout fallback spec",
              "m": "cmux"
            }
          ]
        },
        {
          "title": "In progress",
          "tone": "info",
          "items": [
            {
              "t": "Dispatch pane agent rewrite",
              "m": "#61 \u00b7 cmux"
            }
          ]
        },
        {
          "title": "Blocked",
          "tone": "bad",
          "items": []
        },
        {
          "title": "In review",
          "tone": "ok",
          "items": [
            {
              "t": "Result-file contract",
              "m": "#59 open"
            }
          ]
        }
      ],
      "questions": [
        {
          "id": "q1",
          "q": "Result path: per-agent dir or flat files?",
          "ctx": "Open on the #59 review thread \u2014 flat is simpler, per-agent survives restarts.",
          "resolved": false
        },
        {
          "id": "q2",
          "q": "Adopt handoff-wrapper for paned judges?",
          "ctx": "Resolved yes \u2014 wrapper ships with the dispatch rewrite.",
          "resolved": true
        }
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
              "phase": "Ship",
              "pi": 4,
              "state": "Merged",
              "repo": ".claude",
              "branch": "feat/statusline-wrap",
              "pr": "#78",
              "prState": "Merged",
              "prUrl": "https://github.com/suyatdev/.claude/pull/78",
              "d": {
                "worktree": "removed after merge",
                "diff": "",
                "last": "1w ago",
                "commits": [
                  {
                    "sha": "d4e8a10",
                    "msg": "statusline: wrap segments across rows"
                  }
                ],
                "links": [],
                "checklist": [
                  {
                    "t": "ADR 0018 recorded",
                    "done": true
                  }
                ],
                "notes": "Shipped \u2014 see ADR 0018, the status line may span multiple rows."
              }
            },
            {
              "name": "Worktree segment truncation",
              "desc": "Middle-truncate long worktree paths in the segment",
              "phase": "Ship",
              "pi": 4,
              "state": "Merged",
              "repo": ".claude",
              "branch": "feat/statusline-wrap",
              "pr": "#78",
              "prState": "Merged",
              "prUrl": "https://github.com/suyatdev/.claude/pull/78",
              "d": {
                "worktree": "removed after merge",
                "diff": "",
                "last": "1w ago",
                "commits": [
                  {
                    "sha": "9f11c3b",
                    "msg": "statusline: middle-truncate worktree paths"
                  }
                ],
                "links": [],
                "checklist": [
                  {
                    "t": "Truncation keeps repo + leaf",
                    "done": true
                  }
                ],
                "notes": "Shipped with the wrap PR."
              }
            }
          ]
        }
      ],
      "waves": [
        {
          "n": "1",
          "note": "complete \u2014 both merged in #78",
          "items": [
            {
              "t": "Multi-row wrap layout",
              "pr": "#78",
              "prState": "Merged"
            },
            {
              "t": "Worktree segment truncation",
              "pr": "#78",
              "prState": "Merged"
            }
          ]
        }
      ],
      "constraints": [],
      "branches": [
        {
          "repo": ".claude",
          "branch": "main",
          "wt": "~/dev/.claude",
          "ahead": 0,
          "behind": 0,
          "dirty": false,
          "note": "clean",
          "tone": "ok",
          "last": "1h"
        }
      ],
      "graph": {
        "nodes": [
          {
            "id": "A",
            "label": "Multi-row wrap layout",
            "sub": "#78 merged",
            "tone": "ok",
            "x": 8,
            "y": 60
          },
          {
            "id": "B",
            "label": "Worktree truncation",
            "sub": "#78 merged",
            "tone": "ok",
            "x": 258,
            "y": 60
          }
        ],
        "edges": [
          [
            "A",
            "B"
          ]
        ]
      },
      "kanban": [],
      "questions": [
        {
          "id": "q1",
          "q": "Wrap threshold: cap at 2 rows?",
          "ctx": "Resolved yes \u2014 2 rows max, then truncate segments.",
          "resolved": true
        }
      ]
    },
    {
      "id": "statusline-followups",
      "name": "statusline-followups",
      "dir": "~/.claude/.claude/worktrees/statusline-followups",
      "analyzedAt": "2026-08-20T03:07:28Z",
      "features": [
        {
          "name": "falsifier-base-pin",
          "meta": "6/6",
          "tasks": [
            {
              "name": "1. Red, reproduced on the unfixed script at `main` @ `e0d8546`: **exit\u2026",
              "desc": "1. Red, reproduced on the unfixed script at `main` @ `e0d8546`: **exit 1, 4 `FAIL` rows, and",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #39 (cbb9f60); fix/falsifier-base-pin deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "2. Green: default pinned to `bc7da76`; baseline self-check added before\u2026",
              "desc": "2. Green: default pinned to `bc7da76`; baseline self-check added before any row runs.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #39 (cbb9f60); fix/falsifier-base-pin deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "3. Scenarios A-D verified by execution, `$?` captured immediately (a\u2026",
              "desc": "3. Scenarios A-D verified by execution, `$?` captured immediately (a `$(\u2026)` in the reporting",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #39 (cbb9f60); fix/falsifier-base-pin deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "4. Third branch (base lexer unreadable/unparseable) confirmed\u2026",
              "desc": "4. Third branch (base lexer unreadable/unparseable) confirmed **reachable**, not dead code:",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #39 (cbb9f60); fix/falsifier-base-pin deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "5. Dependent suites unchanged: **492 checks, 0 failed**\u2026",
              "desc": "5. Dependent suites unchanged: **492 checks, 0 failed** (35\u00b777\u00b716\u00b7134\u00b7101\u00b778\u00b751). `bash -n`",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #39 (cbb9f60); fix/falsifier-base-pin deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "6. Observability judge on `d0dac2e` \u2014 **`risk=low confidence=high`**,\u2026",
              "desc": "6. Observability judge on `d0dac2e` \u2014 **`risk=low confidence=high`**, 9/10 pass, one",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #39 (cbb9f60); fix/falsifier-base-pin deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "falsify-harness-signatures",
          "meta": "0/11",
          "tasks": [
            {
              "name": "1. Measure and record both stub baselines **before** any edit, **by\u2026",
              "desc": "1. Measure and record both stub baselines **before** any edit, **by ordinal** \u2014 ids do not",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "2. Add stable ids to all 91 call sites; `ok()`/`bad()` take the id\u2026",
              "desc": "2. Add stable ids to all 91 call sites; `ok()`/`bad()` take the id first so a site cannot omit",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "3. Reason out the flip matrix from the five commits **alone** \u2014 for\u2026",
              "desc": "3. Reason out the flip matrix from the five commits **alone** \u2014 for each of the 15",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "4. Resolve any disagreement from task 3 with evidence from the commit\u2026",
              "desc": "4. Resolve any disagreement from task 3 with evidence from the commit diffs. Never",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "5. Replace `EXPECTED` with `FLIP_MATRIX`; implement the closure check\u2026",
              "desc": "5. Replace `EXPECTED` with `FLIP_MATRIX`; implement the closure check (discriminating set ==",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "6. Implement the vacuity ratchet against **both** stubs; seed each list\u2026",
              "desc": "6. Implement the vacuity ratchet against **both** stubs; seed each list from task 1's",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "7. Prove the harness can fail, **one falsifier per row of \u00a75's table**,\u2026",
              "desc": "7. Prove the harness can fail, **one falsifier per row of \u00a75's table**, driven from the",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "8. Confirm the treadmill is gone: add a throwaway\u2026",
              "desc": "8. Confirm the treadmill is gone: add a throwaway **non-discriminating** passing test, confirm",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "9. Print coverage (15 of 68 load-bearing) alongside the verdict;\u2026",
              "desc": "9. Print coverage (15 of 68 load-bearing) alongside the verdict; document the PR-time run in",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "10. Open the vacuous-assertion follow-up as its own feature file,\u2026",
              "desc": "10. Open the vacuous-assertion follow-up as its own feature file, carrying **both** measured",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "11. Compliance + observability judges, then PR.",
              "desc": "11. Compliance + observability judges, then PR.",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "git-guard-chained-command",
          "meta": "8/8",
          "tasks": [
            {
              "name": "Task 1 \u2014 Add `hooks/git-guard.test.sh` and `hooks/doc-guard.test.sh`\u2026",
              "desc": "Task 1 \u2014 Add `hooks/git-guard.test.sh` and `hooks/doc-guard.test.sh` pinning the chained-command",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/fix-l1",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "Task 2 \u2014 Extract the segment lexer from `classify-pr-command.py` into\u2026",
              "desc": "Task 2 \u2014 Extract the segment lexer from `classify-pr-command.py` into `hooks/lib/shell_segments.py`;",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/fix-l1",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "Task 3 \u2014 Add `hooks/lib/classify-git-command.py` + its unit test,\u2026",
              "desc": "Task 3 \u2014 Add `hooks/lib/classify-git-command.py` + its unit test, implementing the contract above.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/fix-l1",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "Task 4 \u2014 Route `git-guard.sh` (commit guard and push guard) through the\u2026",
              "desc": "Task 4 \u2014 Route `git-guard.sh` (commit guard and push guard) through the classifier.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/fix-l1",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "Task 5 \u2014 Route `doc-guard.sh` through the classifier.",
              "desc": "Task 5 \u2014 Route `doc-guard.sh` through the classifier.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/fix-l1",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "Task 6 \u2014 Widen the git-guard `main` allowlist to `docs/**`.",
              "desc": "Task 6 \u2014 Widen the git-guard `main` allowlist to `docs/**`.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/fix-l1",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "Task 7 \u2014 Update `rules/gates.md`: record the chained-command limit for\u2026",
              "desc": "Task 7 \u2014 Update `rules/gates.md`: record the chained-command limit for git-guard/doc-guard as now",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/fix-l1",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "Task 8 \u2014 Run every hook test suite; confirm all green.",
              "desc": "Task 8 \u2014 Run every hook test suite; confirm all green.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/fix-l1",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "git-guard-detached-head",
          "meta": "11/11",
          "tasks": [
            {
              "name": "Cut the branch from **fetched** `origin/main`. Do not trust a stored\u2026",
              "desc": "Cut the branch from **fetched** `origin/main`. Do not trust a stored count of how far behind",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-detached-head",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "~/.claude/memsearch-freshness",
                "diff": "+56 \u22120",
                "last": "6d ago",
                "commits": [
                  {
                    "sha": "6519441",
                    "msg": "docs(memory): archive session 67 \u2014 restore re-verified, no drift found"
                  },
                  {
                    "sha": "8dac76a",
                    "msg": "docs(memory): record PR #52 merge and branch closeout decision"
                  }
                ],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "**Land the planning measurement scripts in the repository first**,\u2026",
              "desc": "**Land the planning measurement scripts in the repository first**, beside the test suite under",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-detached-head",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "~/.claude/memsearch-freshness",
                "diff": "+56 \u22120",
                "last": "6d ago",
                "commits": [
                  {
                    "sha": "6519441",
                    "msg": "docs(memory): archive session 67 \u2014 restore re-verified, no drift found"
                  },
                  {
                    "sha": "8dac76a",
                    "msg": "docs(memory): record PR #52 merge and branch closeout decision"
                  }
                ],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "Add state helpers to `hooks/git-guard.test.sh` beside `on_branch()`:\u2026",
              "desc": "Add state helpers to `hooks/git-guard.test.sh` beside `on_branch()`: `detached()`, a",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-detached-head",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "~/.claude/memsearch-freshness",
                "diff": "+56 \u22120",
                "last": "6d ago",
                "commits": [
                  {
                    "sha": "6519441",
                    "msg": "docs(memory): archive session 67 \u2014 restore re-verified, no drift found"
                  },
                  {
                    "sha": "8dac76a",
                    "msg": "docs(memory): record PR #52 merge and branch closeout decision"
                  }
                ],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "**First add a `run_case_in <dir> <desc> <want-exit> <cmd>` variant.**\u2026",
              "desc": "**First add a `run_case_in <dir> <desc> <want-exit> <cmd>` variant.** The existing `run_case`",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-detached-head",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "~/.claude/memsearch-freshness",
                "diff": "+56 \u22120",
                "last": "6d ago",
                "commits": [
                  {
                    "sha": "6519441",
                    "msg": "docs(memory): archive session 67 \u2014 restore re-verified, no drift found"
                  },
                  {
                    "sha": "8dac76a",
                    "msg": "docs(memory): record PR #52 merge and branch closeout decision"
                  }
                ],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "Add all **19** matrix rows as `run_case`/`run_case_in` lines. **Run\u2026",
              "desc": "Add all **19** matrix rows as `run_case`/`run_case_in` lines. **Run them and confirm rows 1\u20135,",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-detached-head",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "~/.claude/memsearch-freshness",
                "diff": "+56 \u22120",
                "last": "6d ago",
                "commits": [
                  {
                    "sha": "6519441",
                    "msg": "docs(memory): archive session 67 \u2014 restore re-verified, no drift found"
                  },
                  {
                    "sha": "8dac76a",
                    "msg": "docs(memory): record PR #52 merge and branch closeout decision"
                  }
                ],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "Add `checkout_desc()` (three cases) and `rebase_head_name()`, and\u2026",
              "desc": "Add `checkout_desc()` (three cases) and `rebase_head_name()`, and replace the stderr paths and",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-detached-head",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "~/.claude/memsearch-freshness",
                "diff": "+56 \u22120",
                "last": "6d ago",
                "commits": [
                  {
                    "sha": "6519441",
                    "msg": "docs(memory): archive session 67 \u2014 restore re-verified, no drift found"
                  },
                  {
                    "sha": "8dac76a",
                    "msg": "docs(memory): record PR #52 merge and branch closeout decision"
                  }
                ],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "Rewrite `current_branch()` to use `symbolic-ref`, add\u2026",
              "desc": "Rewrite `current_branch()` to use `symbolic-ref`, add `sequencer_in_progress()` **including the",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-detached-head",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "~/.claude/memsearch-freshness",
                "diff": "+56 \u22120",
                "last": "6d ago",
                "commits": [
                  {
                    "sha": "6519441",
                    "msg": "docs(memory): archive session 67 \u2014 restore re-verified, no drift found"
                  },
                  {
                    "sha": "8dac76a",
                    "msg": "docs(memory): record PR #52 merge and branch closeout decision"
                  }
                ],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "Add the stderr assertions to the test suite, including the third\u2026",
              "desc": "Add the stderr assertions to the test suite, including the third `checkout_desc` rendering on",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-detached-head",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "~/.claude/memsearch-freshness",
                "diff": "+56 \u22120",
                "last": "6d ago",
                "commits": [
                  {
                    "sha": "6519441",
                    "msg": "docs(memory): archive session 67 \u2014 restore re-verified, no drift found"
                  },
                  {
                    "sha": "8dac76a",
                    "msg": "docs(memory): record PR #52 merge and branch closeout decision"
                  }
                ],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "Write ADR 0026, including the rebase-replay residual hole.",
              "desc": "Write ADR 0026, including the rebase-replay residual hole.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-detached-head",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "~/.claude/memsearch-freshness",
                "diff": "+56 \u22120",
                "last": "6d ago",
                "commits": [
                  {
                    "sha": "6519441",
                    "msg": "docs(memory): archive session 67 \u2014 restore re-verified, no drift found"
                  },
                  {
                    "sha": "8dac76a",
                    "msg": "docs(memory): record PR #52 merge and branch closeout decision"
                  }
                ],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "Update the two `rules/gates.md` stubs.",
              "desc": "Update the two `rules/gates.md` stubs.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-detached-head",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "~/.claude/memsearch-freshness",
                "diff": "+56 \u22120",
                "last": "6d ago",
                "commits": [
                  {
                    "sha": "6519441",
                    "msg": "docs(memory): archive session 67 \u2014 restore re-verified, no drift found"
                  },
                  {
                    "sha": "8dac76a",
                    "msg": "docs(memory): record PR #52 merge and branch closeout decision"
                  }
                ],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "Observability judge, then PR. The verdict must stay uncommitted until\u2026",
              "desc": "Observability judge, then PR. The verdict must stay uncommitted until the PR is open",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-detached-head",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "~/.claude/memsearch-freshness",
                "diff": "+56 \u22120",
                "last": "6d ago",
                "commits": [
                  {
                    "sha": "6519441",
                    "msg": "docs(memory): archive session 67 \u2014 restore re-verified, no drift found"
                  },
                  {
                    "sha": "8dac76a",
                    "msg": "docs(memory): record PR #52 merge and branch closeout decision"
                  }
                ],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "git-guard-empty-index",
          "meta": "9/10",
          "tasks": [
            {
              "name": "1. Create the worktree and branch; record the branch in this file's\u2026",
              "desc": "1. Create the worktree and branch; record the branch in this file's frontmatter.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-empty-index",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "2. **Red** \u2014 add failing cases to `hooks/git-guard.test.sh`. At\u2026",
              "desc": "2. **Red** \u2014 add failing cases to `hooks/git-guard.test.sh`. At minimum: docs pathspec commit",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-empty-index",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "3. **Green** \u2014 implement the empty-index file-set derivation in\u2026",
              "desc": "3. **Green** \u2014 implement the empty-index file-set derivation in `hooks/git-guard.sh`, reusing",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-empty-index",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "4. **Red** \u2014 add a failing case to `hooks/phase-guard.test.sh`: a write\u2026",
              "desc": "4. **Red** \u2014 add a failing case to `hooks/phase-guard.test.sh`: a write under",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-empty-index",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "5. **Green** \u2014 add `projects/*/memory/*` to the exempt list at\u2026",
              "desc": "5. **Green** \u2014 add `projects/*/memory/*` to the exempt list at `hooks/phase-guard.sh:285`.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-empty-index",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "6. Write the owed memory file\u2026",
              "desc": "6. Write the owed memory file `feedback_fixture_must_not_pre_create_state` and its",
              "phase": "Review",
              "pi": 3,
              "state": "In review",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-empty-index",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "7. Run both suites plus the neighbouring hook suites and `shellcheck\u2026",
              "desc": "7. Run both suites plus the neighbouring hook suites and `shellcheck -x`; record pass/fail",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-empty-index",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "8. Observability judge (implementation stage), then `gh pr create`.\u2026",
              "desc": "8. Observability judge (implementation stage), then `gh pr create`. User merges in the",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-empty-index",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "9. **RUN 2 \u2192 the design was narrowed.** Verdict appended to the same\u2026",
              "desc": "9. **RUN 2 \u2192 the design was narrowed.** Verdict appended to the same file, pinned `833e3eb`,",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-empty-index",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "10. **RUN 3 \u2192 two more shapes, both fixed here.** Verdict appended to\u2026",
              "desc": "10. **RUN 3 \u2192 two more shapes, both fixed here.** Verdict appended to the same file, pinned",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/git-guard-empty-index",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "global-option-blindness",
          "meta": "15/15",
          "tasks": [
            {
              "name": "0a. Give both hook harnesses a **stdout** assertion, and doc-guard a\u2026",
              "desc": "0a. Give both hook harnesses a **stdout** assertion, and doc-guard a stderr one.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/global-option-blindness",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "0b. Create `hooks/merge-guard.test.sh`, which has never existed, using\u2026",
              "desc": "0b. Create `hooks/merge-guard.test.sh`, which has never existed, using 0a's shared helpers. Pin",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/global-option-blindness",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "0c. Confirm where these suites actually run (a runner script, a git\u2026",
              "desc": "0c. Confirm where these suites actually run (a runner script, a git hook, or by hand) and",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/global-option-blindness",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "1. Red: extend `hooks/lib/classify-git-command.test.py` (exists;\u2026",
              "desc": "1. Red: extend `hooks/lib/classify-git-command.test.py` (exists; **224** lines at `a5de681` \u2014",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/global-option-blindness",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "2. Green: `resolve_subcommand()` + the three tables in\u2026",
              "desc": "2. Green: `resolve_subcommand()` + the three tables in `classify-git-command.py`; emit",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/global-option-blindness",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "3. Red then green: `git-guard.sh` emits the `ask` JSON on\u2026",
              "desc": "3. Red then green: `git-guard.sh` emits the `ask` JSON on `SCOPE_UNKNOWN`, on **every branch**",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/global-option-blindness",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "3b. **The `PRINTS_AND_EXITS` message rule gets built, not just\u2026",
              "desc": "3b. **The `PRINTS_AND_EXITS` message rule gets built, not just written.** Add the set to",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/global-option-blindness",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "4. `doc-guard.sh`: bucket-1 commands become visible; `SCOPE_UNKNOWN`\u2026",
              "desc": "4. `doc-guard.sh`: bucket-1 commands become visible; `SCOPE_UNKNOWN` stays exit 0. **Both",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/global-option-blindness",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "5. Generalise `classify-pr-command.py` to a parameterised pair; prove\u2026",
              "desc": "5. Generalise `classify-pr-command.py` to a parameterised pair; prove `pr create` behaviour is",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/global-option-blindness",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "6. `merge-guard.sh` calls the shared reader. **Prove the OLD behaviour\u2026",
              "desc": "6. `merge-guard.sh` calls the shared reader. **Prove the OLD behaviour first** \u2014 `gh pr merge 5`",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/global-option-blindness",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "7. Re-run the full defect table from this spec and paste the result\u2026",
              "desc": "7. Re-run the full defect table from this spec and paste the result beside the old \u2014 **as the",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/global-option-blindness",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "8. Dependent suites green: `git-guard`, `doc-guard`, **`merge-guard`\u2026",
              "desc": "8. Dependent suites green: `git-guard`, `doc-guard`, **`merge-guard` (new, from 0b)**,",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/global-option-blindness",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "9. \u2757\ud83d\udd34 **BLOCKING manual acceptance test \u2014 user-run, cannot be\u2026",
              "desc": "9. \u2757\ud83d\udd34 **BLOCKING manual acceptance test \u2014 user-run, cannot be automated, and the feature is",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/global-option-blindness",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "10. **ADR 0029** \u2014 the three-bucket rule and why cannot-tell asks\u2026",
              "desc": "10. **ADR 0029** \u2014 the three-bucket rule and why cannot-tell asks instead of allowing.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/global-option-blindness",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "11. Observability judge, then PR. **Judge: risk=low, confidence=high\u2026",
              "desc": "11. Observability judge, then PR. **Judge: risk=low, confidence=high (re-scored once, after a",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/global-option-blindness",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "memory-system-split",
          "meta": "11/12",
          "tasks": [
            {
              "name": "1 \u2014 Model-switch checkpoints \u2014 checkpoint 1 (entering planning) is\u2026",
              "desc": "1 \u2014 Model-switch checkpoints \u2014 checkpoint 1 (entering planning) is moot: planning ran on",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/memory-system-split",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "11 \u2014 Exclude `*.spec.md` from the `docs/features/*.md` glob in\u2026",
              "desc": "11 \u2014 Exclude `*.spec.md` from the `docs/features/*.md` glob in `phase-guard.sh`; extend",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/memory-system-split",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "2 \u2014 Write `hooks/handoff/slim-session-start.sh` + tests; register at\u2026",
              "desc": "2 \u2014 Write `hooks/handoff/slim-session-start.sh` + tests; register at SessionStart. *(Sonnet 5)*",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/memory-system-split",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "3 \u2014 Rewrite `managing-session-memory` \u00a7CODING_MEMORY.md and \u00a7Restore\u2026",
              "desc": "3 \u2014 Rewrite `managing-session-memory` \u00a7CODING_MEMORY.md and \u00a7Restore for the new roles.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/memory-system-split",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "4 \u2014 Write `hooks/feature-sync-guard.sh` + tests; register at PreToolUse\u2026",
              "desc": "4 \u2014 Write `hooks/feature-sync-guard.sh` + tests; register at PreToolUse Bash. **Opus 5.**",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/memory-system-split",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "12 \u2014 Add a registration assertion to `slim-session-start` and\u2026",
              "desc": "12 \u2014 Add a registration assertion to `slim-session-start` and `feature-sync-guard` test",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/memory-system-split",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "5 \u2014 Split **this file** into the pair shape (decision 7). The other 8\u2026",
              "desc": "5 \u2014 Split **this file** into the pair shape (decision 7). The other 8 feature files are not",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/memory-system-split",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "6 \u2014 ADR: supersedes ADR 0006 rows 1 and 15; records the decision-6\u2026",
              "desc": "6 \u2014 ADR: supersedes ADR 0006 rows 1 and 15; records the decision-6 departure from",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/memory-system-split",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "7 \u2014 Rewrite `preparing-pull-requests`:12 (append-to-archive, not\u2026",
              "desc": "7 \u2014 Rewrite `preparing-pull-requests`:12 (append-to-archive, not inherit-context). *(Sonnet 5)*",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/memory-system-split",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "8 \u2014 Update `rules/gates.md` one-canonical-file stub for the pair shape\u2026",
              "desc": "8 \u2014 Update `rules/gates.md` one-canonical-file stub for the pair shape (the MAY, decision 8).",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/memory-system-split",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "9 \u2014 Observability judge (implementation stage), then PR. *(Opus 5,\u2026",
              "desc": "9 \u2014 Observability judge (implementation stage), then PR. *(Opus 5, checkpoint 3)* \u2014 done:",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/memory-system-split",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "10 \u2014 **Phase 2** memsearch work \u2014 separate branch, after Phase 1 merges.",
              "desc": "10 \u2014 **Phase 2** memsearch work \u2014 separate branch, after Phase 1 merges.",
              "phase": "Review",
              "pi": 3,
              "state": "In review",
              "repo": "statusline-followups",
              "branch": "feat/memory-system-split",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "memsearch-freshness",
          "meta": "14/14",
          "tasks": [
            {
              "name": "1 \u2014 Model-switch checkpoint 2 (planning \u2192 implementation); record the\u2026",
              "desc": "1 \u2014 Model-switch checkpoint 2 (planning \u2192 implementation); record the answer here, create",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "1b \u2014 **Regenerate the derived-surface sweep and reconcile it \u2014 first\u2026",
              "desc": "1b \u2014 **Regenerate the derived-surface sweep and reconcile it \u2014 first task after the gate,",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "2 \u2014 Write `docs/decisions/0021-*.md`: adopting a persistent `launchd`\u2026",
              "desc": "2 \u2014 Write `docs/decisions/0021-*.md`: adopting a persistent `launchd` agent as the refresh",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "3 \u2014 Add `run_started`, `last_run`, `last_run_errors` to `status.json`\u2026",
              "desc": "3 \u2014 Add `run_started`, `last_run`, `last_run_errors` to `status.json` (R5), written at both",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "4 \u2014 Extend `hooks/memsearch-nudge.sh` for R1\u2013R4, implementing **R3's\u2026",
              "desc": "4 \u2014 Extend `hooks/memsearch-nudge.sh` for R1\u2013R4, implementing **R3's state table verbatim**.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "5 \u2014 Add the `launchd` template and `memsearch/bin/install-schedule`,\u2026",
              "desc": "5 \u2014 Add the `launchd` template and `memsearch/bin/install-schedule`, install and `--uninstall`",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "6 \u2014 Document `bin/install-schedule` in `memsearch/README.md`, **in the\u2026",
              "desc": "6 \u2014 Document `bin/install-schedule` in `memsearch/README.md`, **in the same commit that adds",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "7 \u2014 **Index `CODING_MEMORY.md` (R10) \u2014 one commit, all seven parts.**\u2026",
              "desc": "7 \u2014 **Index `CODING_MEMORY.md` (R10) \u2014 one commit, all seven parts.** Config: drop it from",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "8 \u2014 Write the five measurement queries and commit them as their own\u2026",
              "desc": "8 \u2014 Write the five measurement queries and commit them as their own commit, before running",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "8b \u2014 **Record the observed scores as a baseline. No pass mark is\u2026",
              "desc": "8b \u2014 **Record the observed scores as a baseline. No pass mark is derived from them.** Run the",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "9 \u2014 Install the agent and run the first scheduled index. Confirm the\u2026",
              "desc": "9 \u2014 Install the agent and run the first scheduled index. Confirm the job is loaded, that",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "10 \u2014 **Two distinct measurements, both recorded under `##\u2026",
              "desc": "10 \u2014 **Two distinct measurements, both recorded under `## Verification`.** They are not the",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "10c \u2014 **Evaluate every falsifier clause and record the result, one line\u2026",
              "desc": "10c \u2014 **Evaluate every falsifier clause and record the result, one line each.** Clauses (a)",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "11 \u2014 Observability judge (implementation stage), then PR.",
              "desc": "11 \u2014 Observability judge (implementation stage), then PR.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "phase-guard-hook",
          "meta": "17/17",
          "tasks": [
            {
              "name": "1. `hooks/phase-guard.test.sh` \u2014 Group A1 examples 1\u20136 (steps 1\u20135 \u2298,\u2026",
              "desc": "1. `hooks/phase-guard.test.sh` \u2014 Group A1 examples 1\u20136 (steps 1\u20135 \u2298, incl. malformed JSON) and",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "2. `hooks/phase-guard.sh` \u2014 steps 1\u20136 (payload, git root,\u2026",
              "desc": "2. `hooks/phase-guard.sh` \u2014 steps 1\u20136 (payload, git root, `docs/features` stat, interpreter",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "3. Test: the core deny (Group B row 1) asserting **exit 2 only**, Group\u2026",
              "desc": "3. Test: the core deny (Group B row 1) asserting **exit 2 only**, Group A1 example 7 (no",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "4. Implement minimal steps 7/9/10: find `phase: planning`, read the\u2026",
              "desc": "4. Implement minimal steps 7/9/10: find `phase: planning`, read the branch, deny with a bare",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "5. Test: the deny-message contract \u2014 all four required elements\u2026",
              "desc": "5. Test: the deny-message contract \u2014 all four required elements (offending path(s) + their",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "6. Implement the deny message to contract. **Green for task 5.** Every\u2026",
              "desc": "6. Implement the deny message to contract. **Green for task 5.** Every later test may now",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "7. Test: Group A3 \u2014 the eight frontmatter-contract scenarios (six\u2026",
              "desc": "7. Test: Group A3 \u2014 the eight frontmatter-contract scenarios (six malformed shapes, optional",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "8. Implement step 7 to the full **Frontmatter contract**. **Green for\u2026",
              "desc": "8. Implement step 7 to the full **Frontmatter contract**. **Green for task 7.**",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "9. Test: Group B's remaining four rows (claimed branch; one feature\u2026",
              "desc": "9. Test: Group B's remaining four rows (claimed branch; one feature planning must not revoke",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "10. Implement step 8: un-superseded filter accepting **`implementation`\u2026",
              "desc": "10. Implement step 8: un-superseded filter accepting **`implementation` or `review`**, the",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "11. Test: Group A2 \u2014 the two audible fail-opens, asserting exactly one\u2026",
              "desc": "11. Test: Group A2 \u2014 the two audible fail-opens, asserting exactly one stderr line, that a",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "12. Implement the once-per-session flag to the **Flag contract**.\u2026",
              "desc": "12. Implement the once-per-session flag to the **Flag contract**. **Green for task 11.**",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "13. Add `/hooks/state/` to `.gitignore`, mirroring `:13`'s\u2026",
              "desc": "13. Add `/hooks/state/` to `.gitignore`, mirroring `:13`'s `/panes/state/` entry and its",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "14. Register the `PreToolUse` / `Edit|Write|NotebookEdit` block in\u2026",
              "desc": "14. Register the `PreToolUse` / `Edit|Write|NotebookEdit` block in `settings.json`. It is a",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "15. **Amend the existing `Phase gate` stub at `rules/gates.md:5`** \u2014\u2026",
              "desc": "15. **Amend the existing `Phase gate` stub at `rules/gates.md:5`** \u2014 not a new bullet. That",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "16. ADR `docs/decisions/0011-*.md` \u2014 amends ADR 0010: records that its\u2026",
              "desc": "16. ADR `docs/decisions/0011-*.md` \u2014 amends ADR 0010: records that its stated objection was",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "17. Dogfood, in a **throwaway repo**, not this one. By task 17 this\u2026",
              "desc": "17. Dogfood, in a **throwaway repo**, not this one. By task 17 this feature's own gate has",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feature/phase-guard-hook",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "post-merge-followups-45",
          "meta": "6/6",
          "tasks": [
            {
              "name": "1 \u2014 `memsearch/README.md:36`: repoint the broken ADR link. The file it\u2026",
              "desc": "1 \u2014 `memsearch/README.md:36`: repoint the broken ADR link. The file it names",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "docs/post-merge-followups-45",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "2 \u2014 Root `README.md`, under `## \ud83d\uddfa\ufe0f Roadmap` immediately after the `#14`\u2026",
              "desc": "2 \u2014 Root `README.md`, under `## \ud83d\uddfa\ufe0f Roadmap` immediately after the `#14` line, add:",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "docs/post-merge-followups-45",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "3 \u2014 `coding-memory/pr-tracking.md:790,794`: PR #45 still reads\u2026",
              "desc": "3 \u2014 `coding-memory/pr-tracking.md:790,794`: PR #45 still reads **open**. Mark it merged at",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "docs/post-merge-followups-45",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "4 \u2014 `coding-memory/observability-judge/verdicts.jsonl`: backfill\u2026",
              "desc": "4 \u2014 `coding-memory/observability-judge/verdicts.jsonl`: backfill `outcome` on the round-5 row",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "docs/post-merge-followups-45",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "`grep -rn \"0018-launchd\" .` returns only the intentional provenance\u2026",
              "desc": "`grep -rn \"0018-launchd\" .` returns only the intentional provenance mentions (ADR 0021's own",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "docs/post-merge-followups-45",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "`python3 -c \"import json;[json.loads(l) for l in\u2026",
              "desc": "`python3 -c \"import json;[json.loads(l) for l in open('coding-memory/observability-judge/verdicts.jsonl')]\"`",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "docs/post-merge-followups-45",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "readme-roadmap-upkeep",
          "meta": "2/2",
          "tasks": [
            {
              "name": "1 \u2014 Edit the three Roadmap lines in `README.md`. No other file.",
              "desc": "1 \u2014 Edit the three Roadmap lines in `README.md`. No other file.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "docs/readme-roadmap-task-tracker",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "2 \u2014 Observability judge at `implementation` stage, then open the PR.",
              "desc": "2 \u2014 Observability judge at `implementation` stage, then open the PR.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "docs/readme-roadmap-task-tracker",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "replay-harness-base-pin",
          "meta": "10/11",
          "tasks": [
            {
              "name": "1. Red \u2014 record the six measured rows above against the unfixed script,\u2026",
              "desc": "1. Red \u2014 record the six measured rows above against the unfixed script, exit codes captured",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/replay-harness-base-pin",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "2. Add the `BASE_REV` third positional; replace the three hard-coded\u2026",
              "desc": "2. Add the `BASE_REV` third positional; replace the three hard-coded `main:` refs.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/replay-harness-base-pin",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "3. Validate extractions: `git-guard.sh` mandatory both sides (success +\u2026",
              "desc": "3. Validate extractions: `git-guard.sh` mandatory both sides (success + non-empty); the two",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/replay-harness-base-pin",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "4. Add the vacuity refusal: a side's set is part 2's required set\u2026",
              "desc": "4. Add the vacuity refusal: a side's set is part 2's required set (guard always, helpers only",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/replay-harness-base-pin",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "5. Resolve `WT` to an absolute path; named error if it does not contain\u2026",
              "desc": "5. Resolve `WT` to an absolute path; named error if it does not contain `hooks/git-guard.sh`.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/replay-harness-base-pin",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "6. Print the resolved base in the header (line 134 pre-fix;\u2026",
              "desc": "6. Print the resolved base in the header (line 134 pre-fix; `replay.sh:236` at HEAD) and the",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/replay-harness-base-pin",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "7. Verify scenarios A-L by execution \u2014 **all twelve, L included** \u2014\u2026",
              "desc": "7. Verify scenarios A-L by execution \u2014 **all twelve, L included** \u2014 `$?` captured immediately,",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/replay-harness-base-pin",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "8. Confirm no dependent suite moved and no file outside the harness\u2026",
              "desc": "8. Confirm no dependent suite moved and no file outside the harness changed.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/replay-harness-base-pin",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "9. ADR 0016; provenance notes on the **five** sites in the part-6 table\u2026",
              "desc": "9. ADR 0016; provenance notes on the **five** sites in the part-6 table \u2014 3 annotated, 1",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/replay-harness-base-pin",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "10. Observability judge, then PR at the judged sha.",
              "desc": "10. Observability judge, then PR at the judged sha.",
              "phase": "Review",
              "pi": 3,
              "state": "In review",
              "repo": "statusline-followups",
              "branch": "fix/replay-harness-base-pin",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "11. Validate the default `worktree` candidate (part 2, revision 10 \u2014\u2026",
              "desc": "11. Validate the default `worktree` candidate (part 2, revision 10 \u2014 was deferral 2).",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/replay-harness-base-pin",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "shell-segments-redirects",
          "meta": "10/10",
          "tasks": [
            {
              "name": "1. Red: `hooks/lib/shell_segments.test.py` \u2014 the suite this module has\u2026",
              "desc": "1. Red: `hooks/lib/shell_segments.test.py` \u2014 the suite this module has never had. Scenarios A-I",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #38 (cc035d2); fix/shell-segments-redirects deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "2. Confirmed red for the stated reason: **14 failed, 17 passed** on the\u2026",
              "desc": "2. Confirmed red for the stated reason: **14 failed, 17 passed** on the unfixed module. The 17",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #38 (cc035d2); fix/shell-segments-redirects deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "3. Green: `_is_redirect()` + redirect-aware split loop in\u2026",
              "desc": "3. Green: `_is_redirect()` + redirect-aware split loop in `shell_segments.py`; trailing",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #38 (cc035d2); fix/shell-segments-redirects deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "4. Dependent suites all green: `git-guard` **77/0**, `doc-guard`\u2026",
              "desc": "4. Dependent suites all green: `git-guard` **77/0**, `doc-guard` **16/0**, `phase-guard`",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #38 (cc035d2); fix/shell-segments-redirects deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "5. Replay: 63 \u00d7 6 = 378 pairs, 378 identical, 0 stricter, 0 relaxed.\u2026",
              "desc": "5. Replay: 63 \u00d7 6 = 378 pairs, 378 identical, 0 stricter, 0 relaxed. **See correction 2 \u2014 this",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #38 (cc035d2); fix/shell-segments-redirects deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "6. End-to-end falsifier, old lexer vs new, driving the real\u2026",
              "desc": "6. End-to-end falsifier, old lexer vs new, driving the real `git-guard.sh`:",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #38 (cc035d2); fix/shell-segments-redirects deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "7a. Observability judge, round 1 on `64ba2fa` \u2014 **`risk=medium\u2026",
              "desc": "7a. Observability judge, round 1 on `64ba2fa` \u2014 **`risk=medium confidence=high`**, and it found",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #38 (cc035d2); fix/shell-segments-redirects deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "7b. Judge round 2 on `28e2053` \u2014 **`risk=low confidence=high`**, 9/10\u2026",
              "desc": "7b. Judge round 2 on `28e2053` \u2014 **`risk=low confidence=high`**, 9/10 pass. PR **#38** opened at",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #38 (cc035d2); fix/shell-segments-redirects deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "8. **ADR 0015** \u2014\u2026",
              "desc": "8. **ADR 0015** \u2014 `docs/decisions/0015-redirections-are-part-of-a-command.md`, amending 0013.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #38 (cc035d2); fix/shell-segments-redirects deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "9. **The accepted limit was written too narrowly a third time.** It is\u2026",
              "desc": "9. **The accepted limit was written too narrowly a third time.** It is *any* trailing bare",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "none  # merged via PR #38 (cc035d2); fix/shell-segments-redirects deleted",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "stale-phase-guard-rule-text",
          "meta": "3/3",
          "tasks": [
            {
              "name": "1. `rules/gates.md:5` \u2014 drop the \"\u26a0\ufe0f Judgment-only in both halves right\u2026",
              "desc": "1. `rules/gates.md:5` \u2014 drop the \"\u26a0\ufe0f Judgment-only in both halves right now \u2026 not registered\"",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/stale-phase-guard-rule-text",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "2. `rules/gates.md:15` \u2014 remove `phase-guard.sh` from the Dormant-hooks\u2026",
              "desc": "2. `rules/gates.md:15` \u2014 remove `phase-guard.sh` from the Dormant-hooks bullet; five \u2192 four.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/stale-phase-guard-rule-text",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "3. `CODING_MEMORY.md:980-989` \u2014 \"FIVE OF THE 17\" \u2192 four of twelve; add\u2026",
              "desc": "3. `CODING_MEMORY.md:980-989` \u2014 \"FIVE OF THE 17\" \u2192 four of twelve; add phase-guard to the",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "fix/stale-phase-guard-rule-text",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "statusline-wrap-worktree",
          "meta": "11/15",
          "tasks": [
            {
              "name": "1. Write the wrap + worktree tests against the **unmodified** script;\u2026",
              "desc": "1. Write the wrap + worktree tests against the **unmodified** script; confirm they fail.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/statusline-wrap-worktree",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "2. Pin the existing injection tests to a wide `COLUMNS` so `nl=0` stays\u2026",
              "desc": "2. Pin the existing injection tests to a wide `COLUMNS` so `nl=0` stays a real assertion",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/statusline-wrap-worktree",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "3. Implement worktree detection and the `wt:(name)` segment.",
              "desc": "3. Implement worktree detection and the `wt:(name)` segment.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/statusline-wrap-worktree",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "4. Implement width tracking at each `extras+=` site.",
              "desc": "4. Implement width tracking at each `extras+=` site.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/statusline-wrap-worktree",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "5. Replace the join/render block with greedy packing.",
              "desc": "5. Replace the join/render block with greedy packing.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/statusline-wrap-worktree",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "6. Update the file's header comment \u2014 the \"Target look\" block and the\u2026",
              "desc": "6. Update the file's header comment \u2014 the \"Target look\" block and the newline rationale,",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/statusline-wrap-worktree",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "7. Full suite green: **68/68**, against a real linked worktree, not a\u2026",
              "desc": "7. Full suite green: **68/68**, against a real linked worktree, not a simulated one.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/statusline-wrap-worktree",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "8a. Observability judge, round 1: **risk=low, confidence=high**, with\u2026",
              "desc": "8a. Observability judge, round 1: **risk=low, confidence=high**, with one real defect \u2014",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/statusline-wrap-worktree",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "8b. Observability judge, round 2: **risk=low, confidence=high**.\u2026",
              "desc": "8b. Observability judge, round 2: **risk=low, confidence=high**. Verified the round-1",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/statusline-wrap-worktree",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "8c. Observability judge, round 3 (delta): **risk=low,\u2026",
              "desc": "8c. Observability judge, round 3 (delta): **risk=low, confidence=high**, all dimensions",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/statusline-wrap-worktree",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "8d. Observability judge, round 4: **risk=low, confidence=high**. Traced\u2026",
              "desc": "8d. Observability judge, round 4: **risk=low, confidence=high**. Traced the segment count",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/statusline-wrap-worktree",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "9. **`statusline-command.falsify.py` reports `FALSIFICATION BROKEN` \u2014\u2026",
              "desc": "9. **`statusline-command.falsify.py` reports `FALSIFICATION BROKEN` \u2014 pre-existing.**",
              "phase": "Review",
              "pi": 3,
              "state": "In review",
              "repo": "statusline-followups",
              "branch": "feat/statusline-wrap-worktree",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "10. **A missed worktree fails into the dangerous reading.** Absence of\u2026",
              "desc": "10. **A missed worktree fails into the dangerous reading.** Absence of `wt:()` is",
              "phase": "Review",
              "pi": 3,
              "state": "In review",
              "repo": "statusline-followups",
              "branch": "feat/statusline-wrap-worktree",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "11. **Absurd `COLUMNS` values print bash arithmetic noise to stderr.**\u2026",
              "desc": "11. **Absurd `COLUMNS` values print bash arithmetic noise to stderr.** A value longer",
              "phase": "Review",
              "pi": 3,
              "state": "In review",
              "repo": "statusline-followups",
              "branch": "feat/statusline-wrap-worktree",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "12. **The row assertion's mutation-sensitivity is\u2026",
              "desc": "12. **The row assertion's mutation-sensitivity is environment-dependent.** Raised by the",
              "phase": "Review",
              "pi": 3,
              "state": "In review",
              "repo": "statusline-followups",
              "branch": "feat/statusline-wrap-worktree",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "tracking-feature-state",
          "meta": "14/14",
          "tasks": [
            {
              "name": "1 \u2014 Spike the injection route. **Fully done, do not re-run**; all four\u2026",
              "desc": "1 \u2014 Spike the injection route. **Fully done, do not re-run**; all four probes ran 2026-08-09.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/tracking-feature-state",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "2 \u2014 Vendor the UI: copy the Nocturne export to `task-tracker/`,\u2026",
              "desc": "2 \u2014 Vendor the UI: copy the Nocturne export to `task-tracker/`, preserving `_ds/`.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/tracking-feature-state",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "3 \u2014 `task-tracker/analyze.py`: features + branches only, importing\u2026",
              "desc": "3 \u2014 `task-tracker/analyze.py`: features + branches only, importing `hooks/lib/feature_tasks.py`.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/tracking-feature-state",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "4 \u2014 `task-tracker/test_analyze.py`: criteria 1 and 2 against a fixture\u2026",
              "desc": "4 \u2014 `task-tracker/test_analyze.py`: criteria 1 and 2 against a fixture repo. Round-11 reopen closed: `repo.card(phase=None)` omits the key, and the converse selector direction is asserted by branch, falsified both ways.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/tracking-feature-state",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "5 \u2014 Waves, constraints and graph derivation, including the `## Depends\u2026",
              "desc": "5 \u2014 Waves, constraints and graph derivation, including the `## Depends on` reader.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/tracking-feature-state",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "6 \u2014 `task-tracker/store.py` + `task-tracker/test_store.py`. Criteria\u2026",
              "desc": "6 \u2014 `task-tracker/store.py` + `task-tracker/test_store.py`. Criteria 3-5.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/tracking-feature-state",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "7 \u2014 `PORTS.md` entry for the control server, before any bind. Port is\u2026",
              "desc": "7 \u2014 `PORTS.md` entry for the control server, before any bind. Port is **8422**.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/tracking-feature-state",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "8 \u2014 `task-tracker/server.py` to the wire contract in \u00a7Design 3. **Task\u2026",
              "desc": "8 \u2014 `task-tracker/server.py` to the wire contract in \u00a7Design 3. **Task 14 runs immediately after this one.** Every route, refusal and startup abort smoke-verified against a cmux shim; task 9 is what pins them as tests. \u26a0\ufe0f **The owed edit landed** (2026-08-11, its own commit ahead of task 9): `confirm_surface()` returns `timeout` separately from `unrunnable`, and `CONFIRM_REFUSAL_REASONS` maps the two states to `confirm_timeout`/`confirm_failed` \u2014 `grep -n CONFIRM_REFUSAL_REASONS task-tracker/server.py`. \u00a7Tasks 8 in the spec half still reads \"owes one edit\"; correcting that is a spec edit, so it waits for `review`.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/tracking-feature-state",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "9 \u2014 `task-tracker/test_server.py`: criteria 6, 7, 9, 10, 11, **12 and\u2026",
              "desc": "9 \u2014 `task-tracker/test_server.py`: criteria 6, 7, 9, 10, 11, **12 and 14**. Not criterion 13. Four files, split at the repo's 800-line ceiling: `test_server.py` (wire contract), `test_server_lifetime.py` (**owns criterion 14** and every startup abort), plus `conftest.py`/`server_harness.py`. Each control was mutation-tested rather than assumed \u2014 six deliberate server defects reverted one at a time, every one caught; re-run by mutating a control and requiring its test to fail. \u26a0\ufe0f **\u00a7Tasks 9's `reason` derivation undercounts, and its stated figures are stale** \u2014 `_run_send` passes `CONFIRM_REFUSAL_REASONS[state]`, a *computed* reason that no literal-matching `grep` sees. That is the \"third emitting shape\" the spec predicted but could not name. Re-derive as the spec's block **plus** `set(server.CONFIRM_REFUSAL_REASONS.values())`, which is what `reasons_emitted_in_source()` in `test_server.py` does; correcting the spec half's own count is a spec edit, queued for `review`.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/tracking-feature-state",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "10 \u2014 Wire the UI's command buttons to `POST /command`; copyable text\u2026",
              "desc": "10 \u2014 Wire the UI's command buttons to `POST /command`; copyable text where no terminal exists. **Owns criterion 15** \u2014 the page's own failure behaviour, which no server test can reach. Handler `0fd5bcd`, buttons `8fe330a`, tests `75b3108` (written and run red first \u2014 twelve failures on the absent marker pair). Criterion 15 is 15 tests in `test_ui_commands.py`, falsified by seven handler mutations of which seven were caught. \u26a0\ufe0f **The handler could not go in a new `.js` file**: the servable set is a closed sixteen-row list pinned in *both* `server.py` and \u00a7Design 3, so a new row is a spec edit and reopens criterion 13; an inline `<script>` dies on the CSP's missing `'unsafe-inline'`. It lives fenced inside the `text/x-dc` block and the test slices it out to load in `node`. **Both render modes were confirmed by an actual headless render, not by inspection** \u2014 served, the header shows three command buttons, zero copy chips and the token once; over `file://`, zero buttons and three copy chips (`/clear`, `/handoff`, `python3 task-tracker/analyze.py .`). No unresolved `{{ }}` binding in either.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/tracking-feature-state",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "11 \u2014 `skills/tracking-feature-state/SKILL.md`. Owns two security\u2026",
              "desc": "11 \u2014 `skills/tracking-feature-state/SKILL.md`. Owns two security controls at launch. Both are written with their failure mode beside them: detaching leaves the parent-death check inert, redirecting `stderr` discards the audit log, and neither shows up in a code read. **The documented launch line was run, not reasoned about** (2026-08-12): `python3 task-tracker/server.py --repo \"$PWD\"` under the harness's background mode bound this session's real surface, served `/` at `200`, and wrote its startup and audit lines to captured `stderr`; `ps -o ppid=` walked the chain to `server \u2192 zsh \u2192 claude`, which is what keeps `getppid()` able to change. **Not verified, and not verifiable here:** trigger-routing accuracy \u2014 the skill is not discoverable from this worktree, and `skills/_standards/authoring-skills-and-agents.md` records that no eval harness exists in this repo.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/tracking-feature-state",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "12 \u2014 Add the skill to the Skills Catalog in `CLAUDE.md`. One row,\u2026",
              "desc": "12 \u2014 Add the skill to the Skills Catalog in `CLAUDE.md`. One row, placed after `managing-session-memory` because both answer \"where does this work stand\"; the catalog is grouped by activity, not alphabetised. `CLAUDE.md` is the only catalog \u2014 every other file mentioning a skill name references it in prose (`grep -rln 'verifying-subagent-commits' --include='*.md' .`), so there is no second list to drift.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/tracking-feature-state",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "13 \u2014 Run every suite, record before/after counts in `## Verification`\u2026",
              "desc": "13 \u2014 Run every suite, record before/after counts in `## Verification` below. All three ran 2026-08-12, **zero failures before or after**; the before-counts came from a throwaway detached checkout of `main` at `1b983d9`, since a run in this tree is an *after* count by definition. `node --version` = v26.5.0, and the `task-tracker/` run reports **no skips at all** \u2014 so criterion 5 got its JS-engine oracle and criterion 15 is verified, not degraded. \u26a0\ufe0f **The guard re-derivation overcounted by one, and is now fixed in place**: `grep -c skipif` totals 15, but `test_server.py:556` guards on `os.geteuid() == 0`, not `node` \u2014 the node-guarded figure is 14, via `grep -h 'skipif(NODE is None' task-tracker/*.py | wc -l`. This lived in the `.md` half, **not** the spec half, so it was never a spec edit; an earlier revision of this note said otherwise and was wrong.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/tracking-feature-state",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "14 \u2014 Vendor all six remote assets \u2014 nine local files. **Runs right\u2026",
              "desc": "14 \u2014 Vendor all six remote assets \u2014 nine local files. **Runs right after task 8**; owns criterion 13. Closed on the re-score in `\u00a7Verification` \u2014 both runs match the revised expectation exactly, on the enumerations already recorded; no new browser run was made.",
              "phase": "Ship",
              "pi": 4,
              "state": "Done",
              "repo": "statusline-followups",
              "branch": "feat/tracking-feature-state",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        },
        {
          "name": "verification-marker-gate",
          "meta": "0/15",
          "tasks": [
            {
              "name": "1. ADR under `docs/decisions/` \u2014 record the marker-as-receipt framing,\u2026",
              "desc": "1. ADR under `docs/decisions/` \u2014 record the marker-as-receipt framing, the three rejected",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "2. Red: `classify-commit-command.test.py` \u2014 **the grammar first**\u2026",
              "desc": "2. Red: `classify-commit-command.test.py` \u2014 **the grammar first** (G1-G9, bundles, value-taking",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "3. Green: `hooks/lib/classify-commit-command.py`.",
              "desc": "3. Green: `hooks/lib/classify-commit-command.py`.",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "4. Red: `write-test-marker.test.py` \u2014 derivation, normalisation,\u2026",
              "desc": "4. Red: `write-test-marker.test.py` \u2014 derivation, normalisation, no-subject skip, atomic write,",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "5. Green: `hooks/lib/write-test-marker.py`.",
              "desc": "5. Green: `hooks/lib/write-test-marker.py`.",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "6. Red: `hooks/test-marker-guard.test.sh` \u2014 every scenario above,\u2026",
              "desc": "6. Red: `hooks/test-marker-guard.test.sh` \u2014 every scenario above, asserting message **and** code.",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "7. Green: `hooks/test-marker-guard.sh`.",
              "desc": "7. Green: `hooks/test-marker-guard.sh`.",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "8. Wire the one-line call into **all 14 paired suites** \u2014 the 11 in\u2026",
              "desc": "8. Wire the one-line call into **all 14 paired suites** \u2014 the 11 in \u00a7Scope's first table plus",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "9. Mutation check \u2014 the 24-mutant floor (14 doors, 9 allow paths,\u2026",
              "desc": "9. Mutation check \u2014 the 24-mutant floor (14 doors, 9 allow paths, emptied classifier); record",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "10. Measure the latency budgets and record **all three** numbers here \u2014\u2026",
              "desc": "10. Measure the latency budgets and record **all three** numbers here \u2014 round 5 added the",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "11. `shellcheck -x` (0.11.0) clean apart from pre-existing findings;\u2026",
              "desc": "11. `shellcheck -x` (0.11.0) clean apart from pre-existing findings; confirm which are",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "12. Gate stub in `rules/gates.md`; `hooks/README.md` entry. Both must\u2026",
              "desc": "12. Gate stub in `rules/gates.md`; `hooks/README.md` entry. Both must state the global-but-inert",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "13. Register in `settings.json` via `update-config`, preserving\u2026",
              "desc": "13. Register in `settings.json` via `update-config`, preserving `\"model\": \"opus[1m]\"`.",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "14. **First-arming check** \u2014 run `hooks/test-marker-guard.sh --status`\u2026",
              "desc": "14. **First-arming check** \u2014 run `hooks/test-marker-guard.sh --status` and expect `ACTIVE` with",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            },
            {
              "name": "15. Obs judge (implementation stage) pinning the final HEAD \u2192 PR.",
              "desc": "15. Obs judge (implementation stage) pinning the final HEAD \u2192 PR.",
              "phase": "Spec",
              "pi": 0,
              "state": "Not started",
              "repo": "statusline-followups",
              "branch": "\u2014",
              "pr": "\u2014",
              "prState": "\u2014",
              "prUrl": "",
              "d": {
                "worktree": "\u2014",
                "diff": "",
                "last": "\u2014",
                "commits": [],
                "links": [],
                "checklist": [],
                "notes": ""
              }
            }
          ]
        }
      ],
      "waves": [
        {
          "n": "1",
          "note": "no declared dependencies \u2014 ordering beyond ## Depends on is unverified",
          "items": [
            {
              "t": "falsifier-base-pin",
              "pr": "",
              "prState": ""
            },
            {
              "t": "falsify-harness-signatures",
              "pr": "",
              "prState": ""
            },
            {
              "t": "git-guard-chained-command",
              "pr": "",
              "prState": ""
            },
            {
              "t": "git-guard-detached-head",
              "pr": "",
              "prState": ""
            },
            {
              "t": "git-guard-empty-index",
              "pr": "",
              "prState": ""
            },
            {
              "t": "global-option-blindness",
              "pr": "",
              "prState": ""
            },
            {
              "t": "memory-system-split",
              "pr": "",
              "prState": ""
            },
            {
              "t": "memsearch-freshness",
              "pr": "",
              "prState": ""
            },
            {
              "t": "phase-guard-hook",
              "pr": "",
              "prState": ""
            },
            {
              "t": "post-merge-followups-45",
              "pr": "",
              "prState": ""
            },
            {
              "t": "readme-roadmap-upkeep",
              "pr": "",
              "prState": ""
            },
            {
              "t": "replay-harness-base-pin",
              "pr": "",
              "prState": ""
            },
            {
              "t": "shell-segments-redirects",
              "pr": "",
              "prState": ""
            },
            {
              "t": "stale-phase-guard-rule-text",
              "pr": "",
              "prState": ""
            },
            {
              "t": "statusline-wrap-worktree",
              "pr": "",
              "prState": ""
            },
            {
              "t": "tracking-feature-state",
              "pr": "",
              "prState": ""
            },
            {
              "t": "verification-marker-gate",
              "pr": "",
              "prState": ""
            }
          ]
        }
      ],
      "constraints": [],
      "branches": [
        {
          "repo": "statusline-followups",
          "branch": "docs/post-merge-53",
          "wt": "\u2014",
          "ahead": 25,
          "behind": 56,
          "dirty": false,
          "note": "needs rebase",
          "tone": "warn",
          "last": "6d"
        },
        {
          "repo": "statusline-followups",
          "branch": "feature/memsearch-freshness",
          "wt": "~/.claude",
          "ahead": 1,
          "behind": 1,
          "dirty": true,
          "note": "5 uncommitted",
          "tone": "bad",
          "last": "5h"
        },
        {
          "repo": "statusline-followups",
          "branch": "feature/verification-marker-gate",
          "wt": "~/.claude/.claude/worktrees/tracking-feature-state",
          "ahead": 45,
          "behind": 0,
          "dirty": true,
          "note": "1 uncommitted",
          "tone": "bad",
          "last": "4m"
        },
        {
          "repo": "statusline-followups",
          "branch": "fix/git-guard-detached-head",
          "wt": "~/.claude/memsearch-freshness",
          "ahead": 2,
          "behind": 34,
          "dirty": false,
          "note": "needs rebase",
          "tone": "warn",
          "last": "6d"
        },
        {
          "repo": "statusline-followups",
          "branch": "fix/tracker-frontmatter-comment",
          "wt": "~/.claude/.claude/worktrees/tracker-frontmatter-comment",
          "ahead": 5,
          "behind": 0,
          "dirty": false,
          "note": "ahead 5",
          "tone": "accent",
          "last": "66m"
        },
        {
          "repo": "statusline-followups",
          "branch": "main",
          "wt": "~/.claude/.claude/worktrees/statusline-followups",
          "ahead": 0,
          "behind": 0,
          "dirty": true,
          "note": "1 uncommitted",
          "tone": "bad",
          "last": "4h"
        }
      ],
      "graph": {
        "nodes": [
          {
            "id": "A",
            "label": "falsifier-base-pin",
            "sub": "none  # merged via PR #39 (cbb9f60); fix/falsifier-base-pin deleted \u00b7 review",
            "tone": "ok",
            "x": 8,
            "y": 8
          },
          {
            "id": "B",
            "label": "falsify-harness-signatures",
            "sub": "no branch \u00b7 planning",
            "tone": "neutral",
            "x": 8,
            "y": 96
          },
          {
            "id": "C",
            "label": "git-guard-chained-command",
            "sub": "fix/fix-l1 \u00b7 review",
            "tone": "ok",
            "x": 8,
            "y": 184
          },
          {
            "id": "D",
            "label": "git-guard-detached-head",
            "sub": "fix/git-guard-detached-head \u00b7 review",
            "tone": "ok",
            "x": 8,
            "y": 272
          },
          {
            "id": "E",
            "label": "git-guard-empty-index",
            "sub": "fix/git-guard-empty-index \u00b7 review",
            "tone": "info",
            "x": 8,
            "y": 360
          },
          {
            "id": "F",
            "label": "global-option-blindness",
            "sub": "feature/global-option-blindness \u00b7 review",
            "tone": "ok",
            "x": 8,
            "y": 448
          },
          {
            "id": "G",
            "label": "memory-system-split",
            "sub": "feat/memory-system-split \u00b7 review",
            "tone": "info",
            "x": 8,
            "y": 536
          },
          {
            "id": "H",
            "label": "memsearch-freshness",
            "sub": "none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09 \u00b7 review",
            "tone": "ok",
            "x": 8,
            "y": 624
          },
          {
            "id": "I",
            "label": "phase-guard-hook",
            "sub": "feature/phase-guard-hook \u00b7 review",
            "tone": "ok",
            "x": 8,
            "y": 712
          },
          {
            "id": "J",
            "label": "post-merge-followups-45",
            "sub": "docs/post-merge-followups-45 \u00b7 review",
            "tone": "ok",
            "x": 8,
            "y": 800
          },
          {
            "id": "K",
            "label": "readme-roadmap-upkeep",
            "sub": "docs/readme-roadmap-task-tracker \u00b7 review",
            "tone": "ok",
            "x": 8,
            "y": 888
          },
          {
            "id": "L",
            "label": "replay-harness-base-pin",
            "sub": "fix/replay-harness-base-pin \u00b7 review",
            "tone": "info",
            "x": 8,
            "y": 976
          },
          {
            "id": "M",
            "label": "shell-segments-redirects",
            "sub": "none  # merged via PR #38 (cc035d2); fix/shell-segments-redirects deleted \u00b7 review",
            "tone": "ok",
            "x": 8,
            "y": 1064
          },
          {
            "id": "N",
            "label": "stale-phase-guard-rule-text",
            "sub": "fix/stale-phase-guard-rule-text \u00b7 review",
            "tone": "ok",
            "x": 8,
            "y": 1152
          },
          {
            "id": "O",
            "label": "statusline-wrap-worktree",
            "sub": "feat/statusline-wrap-worktree \u00b7 review",
            "tone": "info",
            "x": 8,
            "y": 1240
          },
          {
            "id": "P",
            "label": "tracking-feature-state",
            "sub": "feat/tracking-feature-state \u00b7 review",
            "tone": "ok",
            "x": 8,
            "y": 1328
          },
          {
            "id": "Q",
            "label": "verification-marker-gate",
            "sub": "no branch \u00b7 planning",
            "tone": "neutral",
            "x": 8,
            "y": 1416
          }
        ],
        "edges": []
      },
      "kanban": [
        {
          "title": "Up next",
          "tone": "accent",
          "items": [
            {
              "t": "falsify-harness-signatures",
              "m": "statusline-followups \u00b7 0/11"
            },
            {
              "t": "verification-marker-gate",
              "m": "statusline-followups \u00b7 0/15"
            }
          ]
        },
        {
          "title": "In progress",
          "tone": "info",
          "items": []
        },
        {
          "title": "Blocked",
          "tone": "bad",
          "items": []
        },
        {
          "title": "In review",
          "tone": "ok",
          "items": [
            {
              "t": "falsifier-base-pin",
              "m": "statusline-followups \u00b7 6/6"
            },
            {
              "t": "git-guard-chained-command",
              "m": "statusline-followups \u00b7 8/8"
            },
            {
              "t": "git-guard-detached-head",
              "m": "statusline-followups \u00b7 11/11"
            },
            {
              "t": "git-guard-empty-index",
              "m": "statusline-followups \u00b7 9/10"
            },
            {
              "t": "global-option-blindness",
              "m": "statusline-followups \u00b7 15/15"
            },
            {
              "t": "memory-system-split",
              "m": "statusline-followups \u00b7 11/12"
            },
            {
              "t": "memsearch-freshness",
              "m": "statusline-followups \u00b7 14/14"
            },
            {
              "t": "phase-guard-hook",
              "m": "statusline-followups \u00b7 17/17"
            },
            {
              "t": "post-merge-followups-45",
              "m": "statusline-followups \u00b7 6/6"
            },
            {
              "t": "readme-roadmap-upkeep",
              "m": "statusline-followups \u00b7 2/2"
            },
            {
              "t": "replay-harness-base-pin",
              "m": "statusline-followups \u00b7 10/11"
            },
            {
              "t": "shell-segments-redirects",
              "m": "statusline-followups \u00b7 10/10"
            },
            {
              "t": "stale-phase-guard-rule-text",
              "m": "statusline-followups \u00b7 3/3"
            },
            {
              "t": "statusline-wrap-worktree",
              "m": "statusline-followups \u00b7 11/15"
            },
            {
              "t": "tracking-feature-state",
              "m": "statusline-followups \u00b7 14/14"
            }
          ]
        }
      ],
      "questions": [
        {
          "id": "q1",
          "q": "Where is `falsifier-base-pin`'s branch none  # merged via PR #39 (cbb9f60); fix/falsifier-base-pin deleted?",
          "ctx": "The frontmatter names it but no such local branch exists.",
          "resolved": false
        },
        {
          "id": "q2",
          "q": "Where is `git-guard-chained-command`'s branch fix/fix-l1?",
          "ctx": "The frontmatter names it but no such local branch exists.",
          "resolved": false
        },
        {
          "id": "q3",
          "q": "Where is `git-guard-empty-index`'s branch fix/git-guard-empty-index?",
          "ctx": "The frontmatter names it but no such local branch exists.",
          "resolved": false
        },
        {
          "id": "q4",
          "q": "Where is `global-option-blindness`'s branch feature/global-option-blindness?",
          "ctx": "The frontmatter names it but no such local branch exists.",
          "resolved": false
        },
        {
          "id": "q5",
          "q": "Where is `memory-system-split`'s branch feat/memory-system-split?",
          "ctx": "The frontmatter names it but no such local branch exists.",
          "resolved": false
        },
        {
          "id": "q6",
          "q": "Where is `memsearch-freshness`'s branch none  # merged via PR #45 (65ebf81); feature/memsearch-freshness deleted 2026-08-09?",
          "ctx": "The frontmatter names it but no such local branch exists.",
          "resolved": false
        },
        {
          "id": "q7",
          "q": "Where is `phase-guard-hook`'s branch feature/phase-guard-hook?",
          "ctx": "The frontmatter names it but no such local branch exists.",
          "resolved": false
        },
        {
          "id": "q8",
          "q": "Where is `post-merge-followups-45`'s branch docs/post-merge-followups-45?",
          "ctx": "The frontmatter names it but no such local branch exists.",
          "resolved": false
        },
        {
          "id": "q9",
          "q": "Where is `readme-roadmap-upkeep`'s branch docs/readme-roadmap-task-tracker?",
          "ctx": "The frontmatter names it but no such local branch exists.",
          "resolved": false
        },
        {
          "id": "q10",
          "q": "Where is `replay-harness-base-pin`'s branch fix/replay-harness-base-pin?",
          "ctx": "The frontmatter names it but no such local branch exists.",
          "resolved": false
        },
        {
          "id": "q11",
          "q": "Where is `shell-segments-redirects`'s branch none  # merged via PR #38 (cc035d2); fix/shell-segments-redirects deleted?",
          "ctx": "The frontmatter names it but no such local branch exists.",
          "resolved": false
        },
        {
          "id": "q12",
          "q": "Where is `stale-phase-guard-rule-text`'s branch fix/stale-phase-guard-rule-text?",
          "ctx": "The frontmatter names it but no such local branch exists.",
          "resolved": false
        },
        {
          "id": "q13",
          "q": "Where is `statusline-wrap-worktree`'s branch feat/statusline-wrap-worktree?",
          "ctx": "The frontmatter names it but no such local branch exists.",
          "resolved": false
        },
        {
          "id": "q14",
          "q": "Where is `tracking-feature-state`'s branch feat/tracking-feature-state?",
          "ctx": "The frontmatter names it but no such local branch exists.",
          "resolved": false
        },
        {
          "id": "q15",
          "q": "Does `verification-marker-gate` own the branch feature/verification-marker-gate, or should that branch go?",
          "ctx": "The card's frontmatter says branch: none, but feature/verification-marker-gate exists and is named for it. Reported both ways rather than resolved in either direction -- the analyzer never edits a card.",
          "resolved": false
        },
        {
          "id": "q16",
          "q": "Are the merge-order dependencies between these cards actually declared?",
          "ctx": "Dependencies are read only from an explicit `## Depends on` section; prose is never inferred from. 17 of 17 cards declare none, so their ordering is unverified rather than confirmed independent.",
          "resolved": false
        },
        {
          "id": "q17",
          "q": "Is `falsify-harness-signatures` ready to start? It is ordered first but has no branch.",
          "ctx": "Nothing depends on it, so it heads the order, but its frontmatter names no branch -- ordered first is not the same as ready to merge.",
          "resolved": false
        },
        {
          "id": "q18",
          "q": "Should `git-guard-detached-head` rebase before it merges first?",
          "ctx": "It heads the order but its branch is 34 behind main.",
          "resolved": false
        },
        {
          "id": "q19",
          "q": "Is `verification-marker-gate` ready to start? It is ordered first but has no branch.",
          "ctx": "Nothing depends on it, so it heads the order, but its frontmatter names no branch -- ordered first is not the same as ready to merge.",
          "resolved": false
        }
      ]
    }
  ]
};
