# tools

Development-time scripts. Nothing here is needed to *use* `csvkit` — the
library and the CLI depend only on the MoonBit toolchain and
`moonbitlang/x`. These scripts exist so that generated artefacts are
reproducible rather than hand-maintained.

## `gen_differential.py`

Regenerates `testdata/differential.tsv`, the corpus behind the differential
conformance test.

```bash
python3 tools/gen_differential.py
```

Requirements: Python 3.8 or newer. Standard library only — no `pip install`.

### What it produces

One case per line:

```
base64(document) TAB base64(json(records))
```

`document` is a CSV document written by Python's `csv.writer` in the RFC 4180
configuration (`quoting=QUOTE_MINIMAL`, `lineterminator="\r\n"`).
`records` is the table Python's `csv.reader` recovers from that document,
serialised as JSON with `ensure_ascii=False`.

Base64 is used for two reasons: the corpus file can never be mistaken for CSV
by a tool that scans the repository, and embedded CR / LF survive any checkout
setting regardless of `core.autocrlf` or editor configuration.

### Why the corpus exists at all

`csvkit`'s own test suite proves self-consistency: that what we write we can
read back, and that our parser obeys the grammar as we understand it. That is
necessary but not sufficient — a private dialect that is internally coherent
would pass a purely self-referential suite.

The differential corpus supplies **external** evidence. Python's `csv` module is
an independent implementation of the same specification, deployed on an
enormous number of systems. When `csvkit` agrees with it on every one of the
1078 documents, that agreement cannot be explained by our own assumptions.

### Determinism

The seed is fixed at `20260929` and cases are generated in a fixed order, so
two runs produce byte-identical output. CI enforces this: it regenerates the
file and fails if the working tree changed, which catches a corpus that was
edited by hand instead of through the generator.

### The bare-CR exclusion

Python's `csv.writer` will emit a lone `\r` inside an unquoted field. RFC 4180
does not permit that, and `csvkit` rejects it with `UnexpectedLineBreak` — a
deliberate choice, covered by `conformance_test.mbt`.

Rather than relax the parser to match a reference that is more permissive than
the specification, documents containing a bare CR are skipped and the skip is
reported in the script's output. The script counts them and prints the total, so
the exclusion is visible on every run rather than buried. It is also listed in
the README's known limitations.

### Self-check

Before writing a case, the generator verifies that reading back the document it
just wrote reproduces the table it started from. If that ever fails the script
exits non-zero rather than emitting a corpus that encodes a false expectation.

## `report_size.py`

Prints the code-size figures quoted in the submission documents, and (with
`--check`) verifies that the prose still agrees with the sources.

```bash
python3 tools/report_size.py            # print the figures
python3 tools/report_size.py --check    # exit non-zero if a document is stale
```

Requirements: Python 3.8 or newer. Standard library only.

### Why it exists

The documents state how many lines the library, the tests and the CLI occupy.
Those numbers are easy to write by hand and easy to leave behind: after one
round of edits, three documents were quoting three different values for the
same measurement. A reviewer comparing the prose against the repository would
have been right to call that out.

The counting convention is **total lines, blank lines included** — the figure
`wc -l` and GitHub's file view report. That choice is stated here rather than
left implicit, so the number can be reproduced without guessing.

### What it counts

- **library** — `types` / `parser` / `writer` / `diagnostics` / `dialect` /
  `csvkit`, i.e. the root package excluding tests.
- **CLI** — `cmd/main/main.mbt`.
- **tests** — every `*_test.mbt` / `*_wbtest.mbt`.
- **test cases** — `test` blocks, counted by pattern.
- **corpus cases** — non-empty lines in `testdata/differential.tsv`.

## `conformance_report.py`

```
python3 tools/conformance_report.py            # write docs/ecosystem-conformance.md
python3 tools/conformance_report.py --print    # print instead
```

Measures every candidate implementation against the differential corpus and
writes the result. It makes no judgement of its own: the corpus decoding and the
comparison rules come from `conformance.mbt`, reached through
`moon run conformance`.

### Why it is a driver rather than a MoonBit function

A candidate is third-party code, and third-party code can die. `maria/csv_parser`
aborts on a corpus document containing a character outside the Basic Multilingual
Plane, and a MoonBit panic is not a `raise`, so `try`/`catch` never sees it — the
process just ends. Running every candidate in one process would let one library's
crash decide whether the report mentions the others.

So the runner handles one candidate per process and this driver starts a fresh
process for each, with a timeout. A candidate that dies is recorded as `ABORTED`
against its own line and the rest of the report is unaffected.

### Locating a fatal case

When a candidate dies, the driver re-runs it with `--trace`, which makes the
runner print each case immediately *before* handing it to the candidate. The last
line printed therefore names the document that killed it — the difference between
"this library crashed" and something a maintainer can act on.

### Regeneration is checked

CI regenerates the report and fails if the result differs from what is committed.
A third-party result changing is not this project's failure, but a published
document that no longer says what the tool says would be.

