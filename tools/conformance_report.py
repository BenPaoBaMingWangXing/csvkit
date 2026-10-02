#!/usr/bin/env python3
"""Assemble the ecosystem conformance report.

Why this driver exists
----------------------
The conformance runner (`conformance/main.mbt`) deliberately handles exactly one
candidate per process, because a candidate is third-party code and third-party
code can die. That is not a theoretical worry here: `maria/csv_parser` aborts on
a document containing a character outside the Basic Multilingual Plane, and the
abort cannot be caught — MoonBit panics are not `raise`s, so `try`/`catch` never
sees them and the process ends with whatever it had already printed.

Running all candidates in one process would therefore mean one library's crash
decides whether the report mentions the others. This driver starts a fresh
process per candidate, gives each a timeout, and records a candidate that dies
as ABORTED-instead of letting it truncate the report.

What this driver is *not*: it does not decode the corpus and it does not compare
records. Every judgement about conformance comes from the library's own
`conformance.mbt`, reached through the runner. The driver only sequences
processes and lays out text — anything more would be a second opinion nobody
asked for, and could disagree with the one that counts.

Usage::

    python3 tools/conformance_report.py            # write docs/ecosystem-conformance.md
    python3 tools/conformance_report.py --print    # print instead of writing
"""

from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORPUS = os.path.join(ROOT, "testdata", "differential.tsv")
OUT = os.path.join(ROOT, "docs", "ecosystem-conformance.md")

# Generous: a candidate that loops forever should be reported as a hang, not
# hold up the run indefinitely. The reference run takes about a second.
TIMEOUT_SECONDS = 300

SUMMARY_RE = re.compile(r"^(?P<label>.+?): (?P<ok>\d+)/(?P<total>\d+) conform "
                        r"\((?P<div>\d+) divergent, (?P<rej>\d+) rejected\)$")


def run(args: list[str], timeout: int = TIMEOUT_SECONDS):
    """Run a command, returning (exit code, stdout, stderr)."""
    try:
        proc = subprocess.run(
            args, cwd=ROOT, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=timeout,
        )
        return proc.returncode, proc.stdout or "", proc.stderr or ""
    except subprocess.TimeoutExpired:
        return None, "", "timed out after %ds" % timeout


def moon(*args: str):
    return run([os.environ.get("MOON", "moon"), *args])


def candidate_slugs() -> list[tuple[str, str]]:
    """Return (slug, label) pairs in report order."""
    code, out, err = moon("run", "conformance", "--", "--list")
    if code != 0:
        raise SystemExit(
            "could not list candidates\n"
            "  exit: %s\n  stdout: %s\n  stderr: %s" % (code, out.strip(), err.strip())
        )
    pairs = []
    for line in out.splitlines():
        if not line.strip():
            continue
        slug, _, label = line.partition("\t")
        pairs.append((slug.strip(), label.strip() or slug.strip()))
    return pairs


def run_candidate(slug: str, label: str) -> dict:
    """Run one candidate and classify the outcome."""
    code, out, err = moon("run", "conformance", "--", slug)
    lines = out.splitlines()
    summary = None
    for line in lines:
        match = SUMMARY_RE.match(line.strip())
        if match:
            summary = match.groupdict()
            break
    if summary is None:
        # The candidate died. Re-run with tracing to find out where: the last
        # case line printed before the abort names the document that killed it,
        # which turns "it crashed" into something reproducible.
        result = {"slug": slug, "label": label, "status": "aborted",
                  "exit": code, "detail": err.strip(), "samples": []}
        result.update(trace_failure(slug))
        return result
    return {
        "slug": slug,
        "label": summary["label"],
        "status": "ran",
        "exit": code,
        "ok": int(summary["ok"]),
        "total": int(summary["total"]),
        "divergent": int(summary["div"]),
        "rejected": int(summary["rej"]),
        # Sample lines carry their two-space report indent, so the match is made
        # against the raw line rather than the stripped one.
        "samples": [line for line in lines
                    if line.startswith(("  DIVERGENT", "  REJECTED", "  case "))],
    }


def trace_failure(slug: str) -> dict:
    """Re-run a failed candidate with tracing to locate the fatal case.

    Returns `{"fatal_case": int, "fatal_doc": str}` when the position is
    recoverable, and an empty dict otherwise.
    """
    code, out, err = moon("run", "conformance", "--", slug, "--trace")
    fatal = None
    for line in out.splitlines():
        match = re.match(r"^#case (?P<index>\d+) doc=(?P<doc>.*)$", line.strip())
        if match:
            # Keep the last one seen: that is the case the candidate was handed
            # when the process ended.
            fatal = (int(match.group("index")), match.group("doc"))
    if fatal is None:
        return {}
    return {"fatal_case": fatal[0], "fatal_doc": fatal[1]}


def corpus_size() -> int:
    """Count the corpus's non-empty lines.

    Counted here rather than asked of the runner so that the number in the
    report preamble is derived independently of the code that consumes it — if
    the two disagree, the corpus is not what the runner thinks it is.
    """
    with open(CORPUS, encoding="utf-8") as fh:
        return sum(1 for line in fh if line.strip())


def build_report(results: list[dict]) -> str:
    lines = []
    lines.append("# Ecosystem conformance report")
    lines.append("")
    lines.append("Generated by `tools/conformance_report.py`. Do not edit by hand —")
    lines.append("regenerate it.")
    lines.append("")
    lines.append("| | |")
    lines.append("| --- | --- |")
    lines.append("| Corpus | `testdata/differential.tsv`, %d documents |" % corpus_size())
    lines.append("| Reference | Python 3.13 `csv` (see `tools/gen_differential.py`) |")
    lines.append("| Harness | `conformance.mbt` + `conformance/` |")
    lines.append("")
    lines.append("Every implementation was measured with the same corpus, the same")
    lines.append("comparison rules and the same adapter discipline: a candidate's own")
    lines.append("result is flattened to `Array[Array[String]]` by a thin adapter, and")
    lines.append("no adapter normalises a disagreement away. Adapters are commented")
    lines.append("individually in `conformance/adapters.mbt`.")
    lines.append("")
    lines.append("## Results")
    lines.append("")
    lines.append("| Candidate | Conforming | Divergent | Rejected |")
    lines.append("| --- | --- | --- | --- |")
    for result in results:
        if result["status"] != "ran":
            lines.append("| `%s` | **ABORTED** | — | — |" % result["label"])
            continue
        lines.append("| `%s` | %d / %d | %d | %d |" % (
            result["label"], result["ok"], result["total"],
            result["divergent"], result["rejected"],
        ))
    lines.append("")
    lines.append("`Divergent` means the candidate returned different records.")
    lines.append("`Rejected` means it refused a document the reference accepts — a")
    lines.append("divergence in the other direction, and a lossy one, because every")
    lines.append("document in the corpus was produced by an independent implementation")
    lines.append("and read back by it, so every document in it is legal by construction.")
    lines.append("")
    lines.append("A candidate reported as ABORTED did not merely disagree: its process")
    lines.append("died, which is why it is measured in its own process and why the")
    lines.append("fatal case is located separately (see below).")
    lines.append("")
    lines.append("## Raw output")
    lines.append("")
    lines.append("```")
    for result in results:
        if result["status"] != "ran":
            lines.append("%s: ABORTED (exit %s)" % (result["label"], result["exit"]))
            if "fatal_case" in result:
                lines.append("  fatal case %d" % result["fatal_case"])
                lines.append("  doc = %s" % result["fatal_doc"])
            continue
        lines.append("%s: %d/%d conform (%d divergent, %d rejected)" % (
            result["label"], result["ok"], result["total"],
            result["divergent"], result["rejected"],
        ))
        for sample in result["samples"]:
            lines.append(sample.rstrip())
    lines.append("```")
    lines.append("")
    return "\n".join(lines) + "\n"


def main() -> int:
    results = [run_candidate(slug, label) for slug, label in candidate_slugs()]
    report = build_report(results)

    if "--print" in sys.argv:
        sys.stdout.write(report)
        return 0

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(report)
    print("wrote %s" % os.path.relpath(OUT, ROOT))
    for result in results:
        if result["status"] == "ran":
            print("  %-44s %d/%d conform" % (
                result["label"], result["ok"], result["total"],
            ))
        else:
            print("  %-44s ABORTED (exit %s)" % (result["label"], result["exit"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
