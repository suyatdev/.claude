"""How a job fails (docs/features/treko-ledger.spec.md sections 3.5, 3.6, 5.4; decision D53).

Every way a job can fail is one `JobFailure`: the error code the item ends with, the stage it had reached, and the
facts about the failure. `detail_of` turns it into the item's `detail` (section 5.1) and `job_failure_line` into the
one stderr line (section 3.6), which names a code, a stage and an exception class or an errno name, never a message:
a message can hold a path or a field of the request.
"""

from errno import errorcode

LAUNCH_FAILED = "launch_failed"
ANALYSIS_FAILED = "analysis_failed"
MERGE_FAILED = "merge_failed"
STORE_WRITE_FAILED = "store_write_failed"
SCAN_STAGE, MERGE_STAGE, WRITE_STAGE = "scan", "merge", "write"
ANALYZER_STAGES = ("worktrees", "branches", "cards", "order")  # section 6.1, in the order the analyzer reports them
FIRST_ANALYZER_STAGE = ANALYZER_STAGES[0]


class JobFailure(Exception):
    """A job that ends failed. `cause` is the exception class name or the errno name the log line carries."""

    def __init__(self, code, stage, repo=None, exit=None, timed_out=False, errno=None, cause=None):
        super().__init__(code)
        self.code, self.stage, self.repo, self.exit = code, stage, repo, exit
        self.timed_out, self.errno, self.cause = timed_out, errno, cause


def errno_name(error):
    """The symbolic name of an OSError's errno (`ENOENT`), or None when it has no errno or no name for it."""
    return errorcode.get(getattr(error, "errno", None))


def detail_of(failure):
    """The failed item's `detail`, exactly the five keys of section 5.1."""
    return {"stage": failure.stage, "repo": failure.repo, "exit": failure.exit, "timedOut": failure.timed_out,
            "errno": failure.errno}


def job_failure_line(item_id, failure):
    """`server: job <item> <code> <cause> at <stage>`, with no cause (a scan outcome has none) left out."""
    words = ["server: job", item_id, failure.code]
    if failure.cause is not None:
        words.append(failure.cause)
    return " ".join(words + ["at", failure.stage])


def failure_from_error(code, stage, error, repo=None):
    """A failure caused by `error`. An OSError's errno name is both the detail's `errno` and the line's cause; any
    other exception has no errno, so its class name is the cause."""
    name = errno_name(error)
    return JobFailure(code, stage, repo=repo, errno=name, cause=name or type(error).__name__)


def stage_reached(reported):
    """The analyzer stage that was running when the analyzer ended, after it had reported `reported` stages
    finished. Reports come when a stage finishes (section 6.1), so the next one is the one that failed; an analyzer
    that finished all four and still failed (a bad run on stdout, say) failed in the last."""
    return ANALYZER_STAGES[min(reported, len(ANALYZER_STAGES) - 1)]


def analysis_failure(parts):
    """`analysis_failed` for a job whose every part failed: the first failed family's stage, label and exit."""
    first = next(part for part in parts if "failure" in part)
    failed = first["failure"]
    return JobFailure(ANALYSIS_FAILED, failed["stage"], repo=first["label"], exit=failed["exit"],
                      timed_out=failed["timedOut"])
