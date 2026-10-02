"""Report the code-size figures quoted in the submission documents.

Why this exists: the documents quote library / test / CLI line counts and a
test-case count. Those figures were previously written by hand and drifted out
of date when the sources changed -- three documents ended up quoting three
different values for the same thing, which is exactly the kind of mismatch a
reviewer is entitled to catch. This script derives them from the repository.

Counting convention: **total lines, blank lines included** -- the same figure
`wc -l` and GitHub's file view report, so a reviewer can reproduce it without
having to guess which convention the author picked.

Usage:
    python3 tools/report_size.py            # print the figures
    python3 tools/report_size.py --check    # also verify the prose agrees,
                                            # exiting non-zero on a mismatch
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LIBRARY_FILES = [
    "types.mbt",
    "parser.mbt",
    "writer.mbt",
    "diagnostics.mbt",
    "dialect.mbt",
    "csvkit.mbt",
]
CLI_FILE = "cmd/main/main.mbt"

# Documents that quote these figures. Each entry lists the regexes that are
# expected to contain one of our derived numbers, so a stale figure is caught
# rather than silently ignored.
#
# The key is a metric name, or a tuple of metric names when a single sentence
# quotes several figures at once. Keeping the test-case count in here matters
# as much as the line counts: the count moves every time a test is added, and
# a document that lags behind by four is exactly the kind of drift this script
# exists to stop.
PROSE_CHECKS = [
    (
        "README.md",
        [
            # "the corpus (1078 cases, generated)" -- the differential corpus,
            # not the test-case count; derived separately below.
            (r"the corpus \((\d+) cases", "corpus"),
            (r"Total tests: (\d+), passed", "cases"),
            (r"five test suites, (\d+) tests", "cases"),
        ],
    ),
    (
        "SUBMISSION.md",
        [
            (r"实现 (\d+) 行 MoonBit（库 (\d+) \+ CLI (\d+)），测试 (\d+) 行，(\d+) 个测试",
             ("impl_sum", "lib_sum", "cli", "test_sum", "cases")),
            (r"Total tests: (\d+), passed", "cases"),
        ],
    ),
    (
        "AGENTS.md",
        [
            (r"moon test\s+# (\d+) tests", "cases"),
        ],
    ),
]


def total_lines(path):
    with open(path, encoding="utf-8") as fh:
        return len(fh.read().splitlines())


def test_files():
    return sorted(
        f for f in os.listdir(ROOT)
        if f.endswith("_test.mbt") or f.endswith("_wbtest.mbt")
    )


def count_tests(path):
    with open(path, encoding="utf-8") as fh:
        return len(re.findall(r"(?m)^test\s", fh.read()))


def corpus_size():
    """Non-empty lines in the differential corpus = number of cases."""
    path = os.path.join(ROOT, "testdata", "differential.tsv")
    with open(path, encoding="utf-8") as fh:
        return sum(1 for line in fh.read().splitlines() if line.strip())


def collect():
    os.chdir(ROOT)
    lib = {f: total_lines(f) for f in LIBRARY_FILES}
    tests = {f: total_lines(f) for f in test_files()}
    cli = total_lines(CLI_FILE)
    return {
        "library": lib,
        "tests": tests,
        "cli": cli,
        "lib_sum": sum(lib.values()),
        "test_sum": sum(tests.values()),
        "impl_sum": sum(lib.values()) + cli,
        "cases": sum(count_tests(f) for f in tests),
        "corpus": corpus_size(),
    }


def report(m):
    print("csvkit code size (total lines, blank lines included)")
    print("=" * 58)
    print("library")
    for name, n in m["library"].items():
        print("  %-24s %5d" % (name, n))
    print("  %-24s %5d" % ("subtotal", m["lib_sum"]))
    print("CLI")
    print("  %-24s %5d" % (os.path.basename(CLI_FILE), m["cli"]))
    print("  %-24s %5d" % ("implementation total", m["impl_sum"]))
    print("tests")
    for name, n in m["tests"].items():
        print("  %-24s %5d" % (name, n))
    print("  %-24s %5d" % ("subtotal", m["test_sum"]))
    print()
    print("test cases: %d" % m["cases"])
    print("corpus cases: %d" % m["corpus"])
    print()
    print("Tests exceed the implementation. That is deliberate: the")
    print("correctness claim rests on breadth of evidence, not on brevity.")


def check(m):
    """Verify the documents quote the derived figures."""
    bad = []
    for name, pats in PROSE_CHECKS:
        path = os.path.join(ROOT, name)
        if not os.path.exists(path):
            continue
        body = open(path, encoding="utf-8").read()
        for pat, key in pats:
            hit = re.search(pat, body)
            if not hit:
                bad.append("%s: pattern %r not found" % (name, pat))
                continue
            keys = key if isinstance(key, tuple) else (key,)
            if len(hit.groups()) != len(keys):
                bad.append(
                    "%s: pattern %r captures %d groups but names %d metrics"
                    % (name, pat, len(hit.groups()), len(keys))
                )
                continue
            for captured, metric in zip(hit.groups(), keys):
                got = int(captured)
                if got != m[metric]:
                    bad.append(
                        "%s: says %s = %d, repository says %d"
                        % (name, metric, got, m[metric])
                    )
    for line in bad:
        print("MISMATCH  %s" % line, file=sys.stderr)
    if not bad:
        print("prose figures agree with the repository.")
    return 1 if bad else 0


def main():
    old = os.getcwd()
    try:
        m = collect()
        report(m)
        if "--check" in sys.argv:
            return check(m)
        return 0
    finally:
        os.chdir(old)


if __name__ == "__main__":
    sys.exit(main())
