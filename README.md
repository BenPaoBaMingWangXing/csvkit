# csvkit

**RFC 4180 CSV parsing and serialization for MoonBit.**

[![CI](https://github.com/BenPaoBaMingWangXing/csvkit/actions/workflows/ci.yml/badge.svg)](https://github.com/BenPaoBaMingWangXing/csvkit/actions/workflows/ci.yml)
[![license: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

`csvkit` reads and writes the CSV format defined by
[RFC 4180](https://www.rfc-editor.org/rfc/rfc4180) (with
[errata 5664](https://www.rfc-editor.org/errata/eid5664)). It is a small library
with an explicit error model, no hidden state, and one hard guarantee:

```
parse(serialize(table)) == table
```

There is a command line tool as well, so the library can be exercised without
writing MoonBit.

## Why this library exists

CSV looks trivial and is not. The format is defined by a one-page RFC whose
grammar has three properties that trip up naive implementations:

1. A field may contain the delimiter, a doubled quote, CR and LF — but only if
   it is quoted. A newline inside a quoted field means a line-oriented
   `split("\n")` parser is simply wrong.
2. Only a `"` *after* a closing `"` (forming `""`) is an escape. Text after a
   closing quote (`"abc"def`) is malformed, and a `"` that is not the first
   character of a field begins nothing.
3. The trailing `CRLF` is optional, so a file that ends on a separator has one
   fewer record than a naive count suggests — and `""` has no records at all.

Most CSV bugs in the wild are one of these three. `csvkit` handles all of them
explicitly and agrees with an independent implementation on a
1078-document corpus (see [External consistency](#external-consistency)).

## Install

This package is **not published to the mooncakes registry yet**, so
`moon add BenPaoBaMingWangXing/csvkit` will fail with
`Could not find the latest published version`. Publishing is tracked in
[issue #2](https://github.com/BenPaoBaMingWangXing/csvkit/issues/2). Until then,
use it as a path dependency:

```bash
git clone https://github.com/BenPaoBaMingWangXing/csvkit
cd csvkit
moon check --deny-warn && moon test
```

To depend on it from another project, add a path dependency in that project's
`moon.mod.json`:

```json
"deps": { "BenPaoBaMingWangXing/csvkit": { "path": "../csvkit" } }
```

Requires `moon` 0.1.20260904 or newer (`moon version --all`). The library
package depends only on the MoonBit core library; `moonbitlang/x` is used only
by the CLI and by one test.

## Usage

### Parsing

```moonbit
let rows = @csvkit.parse("name,city\r\nAlice,\"Paris, FR\"\r\n").unwrap()
inspect(rows.length(), content="2")
inspect(rows[1][1], content="Paris, FR")
```

`parse` returns `Result[Table, CsvError]` — it never panics and never silently
drops input. Errors carry a source position:

```moonbit
match @csvkit.parse("a,\"unterminated") {
  Err(e) => println(e.to_message())
  // unterminated quoted field at line 1, column 3
  Ok(_) => ()
}
```

### Serializing

```moonbit
let table : @csvkit.Table = [["name", "city"], ["Alice", "Paris, FR"]]
let text = @csvkit.serialize(table)
// name,city\r\nAlice,"Paris, FR"\r\n
```

Fields are quoted when they contain the delimiter, a quote, CR, LF, or leading
or trailing whitespace. That last case is defensive: many readers trim
whitespace, which would break the round-trip guarantee.

### Strict validation

Parsing is permissive, because RFC 4180 does not require every record to have
the same number of fields. Validating that is a separate, opt-in step:

```moonbit
match @csvkit.parse_strict("a,b\r\nc\r\n") {
  Err(FieldCountMismatch(line~, expected~, actual~)) =>
    println("line \{line}: \{actual} of \{expected}")
  _ => ()
}
```

### Dialects

The parts RFC 4180 leaves open are configurable. `parse(s)` is exactly
`parse_with(s, Dialect::rfc4180())`.

| Constructor | Delimiter | Records separated by | BOM |
|---|---|---|---|
| `Dialect::rfc4180()` | `,` | CRLF, LF or CR | preserved |
| `Dialect::strict_crlf()` | `,` | CRLF only | preserved |
| `Dialect::strict_lf()` | `,` | LF only | preserved |
| `Dialect::semicolon()` | `;` | CRLF, LF or CR | preserved |
| `Dialect::tab()` | tab | CRLF, LF or CR | preserved |
| `Dialect::excel()` | `,` | CRLF, LF or CR | **stripped** |

```moonbit
let rows = @csvkit.parse_with("a;\"b;b\";c\r\n", @csvkit.Dialect::semicolon()).unwrap()
inspect(rows[0].length(), content="3")
inspect(rows[0][1], content="b;b")
```

The default dialect accepting three separator forms is a deliberate choice
rather than hidden leniency: files in the wild use bare LF constantly, and the
`strict_*` dialects are there for callers who need the literal reading. See
[`docs/conformance.md`](docs/conformance.md).

### Diagnostics

Structural checks that RFC 4180 does not define are grouped in `diagnose`, and
return data rather than printing:

```moonbit
let report = @csvkit.diagnose(rows)
if not(report.is_clean()) {
  for line in report.to_lines() { println(line) }
}
```

The split between `CsvError` and `Issue` matters: a malformed document has no
reasonable interpretation and fails to parse, while a *well-formed but odd*
document — a ragged row, a blank line — parses to a perfectly usable table and
is reported separately. The library does not decide which of those is fatal.
See [`docs/design.md`](docs/design.md) §2.

## Command line tool

```
csvkit count <file>     number of records, fields and columns
csvkit check <file>     structural diagnostics, one per line
csvkit csv <file>       re-serialize through the library to stdout
csvkit version          print the library version
```

Exit codes: `0` success, `1` a CSV error or a reported issue, `2` a usage or I/O
error. A malformed file and a mistyped command are different failures and should
be distinguishable without parsing stderr text.

```console
$ moon run cmd/main -- count examples/people.csv
records: 5
fields:  13
columns: 3
issues:  1

$ moon run cmd/main -- check examples/people.csv
line 4: ragged, expected 3 fields, found 1
```

All four subcommands were run from a clean checkout on Windows (wasm target)
and on the ubuntu CI runner; `count` and `csv` exit `0`, `check` exits `1` on
the deliberately ragged `examples/people.csv`, and an unknown subcommand exits
`2` with a usage message. Every command in this README was executed before
being written down; none are aspirational.

## External consistency

Correctness claims about a parser are worth what the evidence behind them is
worth, so this repository ships its evidence and the script that regenerates it.

A test suite can only demonstrate self-consistency: that what we write we can
read, and that our parser obeys the grammar as we understand it. A private
dialect that is internally coherent would pass such a suite perfectly.

**Method.** `tools/gen_differential.py` generates **1078 documents** using
Python 3.13's `csv.writer` (`quoting=QUOTE_MINIMAL`, `lineterminator="\r\n"`),
covering single fields from a fixed vocabulary, empty fields in every position,
embedded delimiters, doubled quotes, embedded CRLF and bare LF, tabs, and
multibyte UTF-8. For each document it records what Python's `csv.reader`
recovers. `csvkit` must reproduce that exactly, field for field.

**Result.** All 1078 documents agree. The same corpus is used to check
`parse(serialize(t)) == t`, so the writer is verified against externally
generated data rather than against its own output.

Because the expectations were produced by code we did not write, the agreement
cannot be explained by our own assumptions. That is what makes this the
strongest evidence in the repository.

```bash
python3 tools/gen_differential.py    # regenerate testdata/differential.tsv
moon test                            # includes "differential: ..."
```

The generator is deterministic (seed `20260929`), and CI fails if regenerating
changes the checked-in file — so a corpus edited by hand is caught. Regenerating
requires Python; **running the tests does not**, because the corpus is checked
in.

### Test suite

```
$ moon test
Total tests: 64, passed: 64, failed: 0.
```

Tests are split by the kind of claim they make:

| File | Tests | What it establishes |
|---|---|---|
| `conformance_test.mbt` | 28 | Grammar conformance, each case traced to RFC 4180 §2 |
| `conformance_differential_test.mbt` | 2 | Agreement with an independent implementation |
| `conformance_harness_test.mbt` | 4 | The conformance layer itself |
| `writer_test.mbt` | 13 | Quoting rules and round-trip behaviour |
| `diagnostics_test.mbt` | 17 | Structural reports |

[`docs/conformance.md`](docs/conformance.md) maps each clause of RFC 4180 to the
test that pins it, and states plainly which clauses are deliberately not
enforced. Every test name it cites is a real one.

CI additionally runs `moon check --deny-warn`, a build of every target
(`wasm`, `wasm-gc`, `js`, `native`), the CLI, corpus reproducibility, and
`moon package`.

## Conformance layer

The corpus above is not useful only to this library. `conformance.mbt` turns it
into an instrument: it decodes the corpus, applies one set of comparison rules,
and measures *any* implementation of the same grammar that can flatten its
result to `Array[Array[String]]`.

```moonbit
pub(open) trait CsvCandidate {
  label(Self) -> String
  parse(Self, String) -> Result[Array[Array[String]], String]
}

pub fn[T : CsvCandidate] run_corpus(
  candidate : T,
  cases : Array[CorpusCase],
  on_case : ((Int) -> Unit)?,
) -> Summary
```

An adapter is meant to be thin, and to be honest about the one thing it has to
absorb. `mbitsv` models a document as a header plus body rows; comparing its
body rows against a headerless corpus would report every document as missing
its first record, which would be a claim about an API design rather than about
parsing. The adapter turns the header/body split off and says so in a comment.
No adapter normalises a disagreement away — an adapter that did would be worse
than no report, because it would manufacture a pass.

Run it against the implementations that already existed:

```
$ moon run conformance -- --list
csvkit
maria
mbitsv-default
mbitsv-strict-off

$ moon run conformance -- maria
$ python3 tools/conformance_report.py        # regenerates the full report
```

One candidate per process, deliberately. A candidate is third-party code and
third-party code can die: `maria/csv_parser` aborts on a document containing a
character outside the Basic Multilingual Plane, and a MoonBit panic is not a
`raise`, so `try`/`catch` does not see it. In a single process that abort would
take the whole report with it. `tools/conformance_report.py` starts a fresh
process per candidate and locates the fatal case by re-running with tracing.

Results are published unedited in
[`docs/ecosystem-conformance.md`](docs/ecosystem-conformance.md). The survey
behind the choice of candidates — what exists, what overlaps, and what does
not — is in [`docs/RESEARCH.md`](docs/RESEARCH.md).

## Known limitations

These are deliberate and, where they are testable, asserted in tests rather than
left implicit:

- **No streaming API.** `parse` takes a whole `String`. A streaming reader is
  the obvious next step and is not implemented; for large files, memory use is
  proportional to the entire document.
- **A bare CR inside an unquoted field is rejected.** It is consumed as a record
  separator instead. RFC 4180 has no way to express a lone CR in an unquoted
  field, so this is a property of the format, not of the implementation. It is
  also why the differential corpus excludes documents containing one — Python's
  writer emits them, the specification does not permit them, and the parser was
  not relaxed to match. `tools/gen_differential.py` prints the exclusion count
  on every run.
- **No type inference.** Every field is a `String`. Converting to numbers, dates
  or an on-disk schema is left to the caller, on purpose: guessing types is
  where CSV libraries usually become surprising.
- **No delimiter auto-detection.** The dialect must be chosen by the caller.
  Detection is a heuristic that belongs in a separate layer with its own tests.
- **`looks_like_header` is a heuristic, not a decision procedure.** The format
  carries no marker distinguishing a header from a data row, so nothing can
  decide it reliably. The function is conservative and documented as a guess.
- **Column positions count characters, not bytes or display columns.** For text
  containing combining marks or East Asian wide characters, the reported column
  will not match a terminal's cursor position.
- **The UTF-8 decoding is whatever `String` provides.** Input that is not valid
  UTF-8 cannot reach these functions, so `CsvError` has no UTF-8 variant.
- **No benchmarks.** Performance has not been measured, so no performance claim
  is made.

## Repository layout

```
csvkit.mbt                        library root (version)
types.mbt                         Row, Table, Position, CsvError
dialect.mbt                       Dialect, RecordSeparator
parser.mbt                        the scanner
writer.mbt                        the serializer
diagnostics.mbt                   Issue, HeaderProblem, Report
*_test.mbt                        five test suites, 64 tests
conformance.mbt                   the conformance layer (corpus, comparison, trait)
conformance/                      adapters for other implementations + runner
cmd/main/                         the command line tool
examples/people.csv               sample input for the CLI
testdata/differential.tsv         the corpus (1078 cases, generated)
tools/gen_differential.py         regenerates the corpus
docs/design.md                    why the design is the way it is
docs/conformance.md               RFC clause -> test matrix
docs/ecosystem-conformance.md     measured results for other implementations
tools/conformance_report.py       regenerates that report
NOTICE                            provenance
SECURITY.md                       threat model and reporting
CHANGELOG.md                      release notes
```

## License and provenance

Licensed under the [Apache License, Version 2.0](LICENSE).

This is an original implementation in MoonBit. It is a faithful implementation
of the format specified by RFC 4180, which is a document, not code; no source
code was ported from another project, and no code was translated from another
language. See [NOTICE](NOTICE) for the full provenance statement, including the
role Python's `csv` module plays as a test oracle.

## API summary

| Symbol | Signature |
|---|---|
| `parse` | `(String) -> Result[Table, CsvError]` |
| `parse_with` | `(String, Dialect) -> Result[Table, CsvError]` |
| `parse_strict` | `(String) -> Result[Table, CsvError]` |
| `serialize` | `(Table) -> String` |
| `serialize_with` | `(Table, Dialect) -> String` |
| `serialize_row` | `(Row, Dialect) -> String` |
| `check_field_counts` | `(Table) -> Result[Table, CsvError]` |
| `count_fields_per_record` | `(String) -> Result[Array[Int], CsvError]` |
| `needs_quoting` | `(String, Dialect) -> Bool` |
| `diagnose` | `(Table) -> Report` |
| `looks_like_header` | `(Table) -> Bool` |
| `version` | `() -> String` |
| `CsvError::to_message` | `(CsvError) -> String` |
| `Report::is_clean` | `(Report) -> Bool` |
| `Report::to_lines` | `(Report) -> Array[String]` |

Types: `Row = Array[String]`, `Table = Array[Row]`, plus `Dialect`,
`RecordSeparator`, `CsvError`, `Position`, `Issue`, `HeaderProblem`, `Report`.
The generated interface is authoritative: `pkg.generated.mbti`.
