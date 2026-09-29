#!/usr/bin/env python3
"""Regenerate ``testdata/differential.tsv``.

Why this file exists
--------------------
The differential test is the repository's *external* consistency evidence. It
compares ``csvkit`` against Python's standard-library ``csv`` module, which is
an independent, very widely deployed implementation of the same grammar
(RFC 4180). Agreeing with it field-for-field is much stronger evidence than
round-tripping our own output through our own parser, because a private
dialect that is internally consistent would pass a self-test and fail here.

Format
------
One case per line::

    base64(document) TAB base64(json(records))

Everything is base64-encoded so the corpus file can never be mistaken for the
CSV it describes, and so embedded CR / LF survive any checkout setting
(``core.autocrlf``, EditorConfig, Windows editors, and so on). The records are
serialised with ``json.dumps(..., ensure_ascii=False)`` plus ``sort_keys``-free
plain output; the MoonBit loader in ``conformance_differential_test.mbt``
parses exactly that subset.

Determinism
-----------
The seed is fixed and every case is generated in a fixed order, so running this
script twice produces byte-identical output. CI relies on that: if
``testdata/differential.tsv`` differs after regeneration, the checked-in file
was edited by hand.

The one deliberate exclusion: bare CR
-------------------------------------
Python's ``csv.writer`` will happily write a lone ``\\r`` inside an unquoted
field. RFC 4180 does not permit a bare CR there, and ``csvkit`` rejects it as
``UnexpectedLineBreak`` -- that rejection is intentional and is covered by
``conformance_test.mbt``. Rather than weaken the parser to match a reference
that is more permissive than the RFC, cases containing a bare CR are excluded
from the corpus. The exclusion is stated here and in the README's list of known
limitations so that it is a documented decision rather than a silent one.

Usage::

    python3 tools/gen_differential.py
"""

from __future__ import annotations

import base64
import csv
import io
import json
import os
import random
import sys

SEED = 20260929

# Field vocabularies sampled to build documents. Grouped by the quoting rule
# each one probes, so the corpus covers the grammar systematically instead of
# relying on random bytes to stumble onto the interesting cases.
PLAIN = ["a", "b", "c", "abc", "x1", "2026-09-29", "0", "-1", "3.14", "true"]

# Fields whose content forces the writer to quote: the delimiter, the quote
# character, or an embedded line break.
NEEDS_QUOTING = [
    "a,b",            # delimiter
    'say "hi"',       # quote character
    '"',              # a lone quote
    '""',             # two quotes
    'a"b',            # quote in the middle
    "line1\nline2",   # embedded LF
    "line1\r\nline2", # embedded CRLF
    "trailing\n",     # embedded LF at the very end
    "\nleading",      # embedded LF at the very start
    "a\r\nb\r\nc",    # two embedded CRLFs
]

# Awkward but legal field values: empty, whitespace-only, and non-ASCII.
EDGE = [
    "",
    " ",
    "  ",
    "\t",
    "a\tb",
    "é",
    "中文",
    "安枢",
    "café",
    "🙂",
    "a\u00a0b",  # non-breaking space
]

# Shapes that probe empty fields and trailing/leading delimiters.
SHAPES = [
    [""],                  # a single empty field
    ["", ""],              # two empty fields
    ["a", ""],             # trailing empty
    ["", "a"],             # leading empty
    ["", "", ""],          # three empty fields
    ["a", "", "c"],        # empty in the middle
]


def base64_text(s: str) -> str:
    return base64.b64encode(s.encode("utf-8")).decode("ascii")


def json_text(records) -> str:
    return json.dumps(records, ensure_ascii=False)


def write_document(records) -> str:
    """Serialise with Python's csv module in the RFC 4180 configuration."""
    buf = io.StringIO()
    writer = csv.writer(buf, quoting=csv.QUOTE_MINIMAL, lineterminator="\r\n")
    writer.writerows(records)
    return buf.getvalue()


def read_document(doc: str):
    """Recover records with Python's csv module, the reference answer."""
    reader = csv.reader(io.StringIO(doc, newline=""), strict=False)
    return [row for row in reader]


def contains_bare_cr(doc: str) -> bool:
    """True if the document has a CR that is not part of a CRLF.

    Such documents are excluded: ``csvkit`` rejects a bare CR in an unquoted
    field as a malformed line break, while Python's writer emits one. See the
    module docstring.
    """
    i = 0
    while i < len(doc):
        if doc[i] == "\r":
            if i + 1 < len(doc) and doc[i + 1] == "\n":
                i += 2
                continue
            return True
        i += 1
    return False


def build_cases(rng: random.Random):
    """Yield candidate record-tables in a fixed, seed-driven order."""
    pool = PLAIN + NEEDS_QUOTING + EDGE

    # 1. Every single-field table, so each vocabulary entry is pinned alone.
    for value in pool:
        yield [[value]]

    # 2. The structural shapes: empties in every position.
    for shape in SHAPES:
        yield [list(shape)]

    # 3. Two-field and three-field combinations from the smaller vocabularies,
    #    exhaustively for the interesting (quoting/edge) values.
    small = NEEDS_QUOTING + EDGE
    for a in small:
        for b in small:
            yield [[a, b]]

    for a in NEEDS_QUOTING[:6]:
        for b in PLAIN[:4]:
            for c in EDGE[:5]:
                yield [[a, b, c]]

    # 4. Multi-record tables, including mismatched field counts (which RFC 4180
    #    allows; raggedness is a diagnostics concern, not a parse error).
    multi = [
        [["a", "b"], ["c", "d"]],
        [["a"], ["b"], ["c"]],
        [[""], [""]],
        [["", ""], ["", ""]],
        [["name", "note"], ["Alice", 'said "hi"'], ["Bob", "a,b"]],
        [["h1", "h2", "h3"], ["r1", "r2"]],
        [["only"], ["two", "fields"], ["three", "f", "g"]],
    ]
    for table in multi:
        yield table

    # 5. Randomised tables, widening coverage beyond the hand-written lists.
    for _ in range(340):
        nrows = rng.randint(1, 4)
        table = []
        for _ in range(nrows):
            ncols = rng.randint(1, 5)
            table.append([rng.choice(pool) for _ in range(ncols)])
        yield table

    # 6. Randomised tables drawn only from the quoting/edge vocabulary, where
    #    the writer's decisions are densest.
    for _ in range(200):
        nrows = rng.randint(1, 3)
        table = []
        for _ in range(nrows):
            ncols = rng.randint(1, 4)
            table.append([rng.choice(small) for _ in range(ncols)])
        yield table


def main() -> int:
    rng = random.Random(SEED)
    here = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(os.path.dirname(here), "testdata", "differential.tsv")

    lines = []
    skipped_bare_cr = 0
    seen = set()

    for table in build_cases(rng):
        doc = write_document(table)
        if contains_bare_cr(doc):
            skipped_bare_cr += 1
            continue
        expected = read_document(doc)
        # Cross-check the generator against itself: reading back what we wrote
        # must reproduce the table we started from. If this ever fails the
        # corpus would be encoding a lie, so it is a hard error.
        if expected != table:
            print(
                f"generator self-check failed:\n  wrote {table!r}\n  read  {expected!r}",
                file=sys.stderr,
            )
            return 1
        key = base64_text(doc)
        if key in seen:
            continue
        seen.add(key)
        lines.append(f"{key}\t{base64_text(json_text(expected))}")

    with open(out_path, "w", encoding="ascii", newline="\n") as fh:
        fh.write("\n".join(lines))
        fh.write("\n")

    print(f"wrote {out_path}")
    print(f"  cases:            {len(lines)}")
    print(f"  skipped (bare CR): {skipped_bare_cr}")
    print(f"  seed:             {SEED}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
