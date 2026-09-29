# Design notes

Why `csvkit` is built the way it is. This document records decisions that a
reader of the source would otherwise have to reverse-engineer, especially the
places where a plausible alternative was rejected.

---

## 1. Scope: the specification is the product

RFC 4180 is about twelve lines of ABNF. It is tempting to treat a CSV library as
a solved, trivial problem — read a line, split on commas — and then pad the
result with features until it looks substantial. That instinct produces the
worst kind of submission: broad, shallow, and unverifiable.

The opposite decision was taken here. `csvkit` implements RFC 4180 and its
erratum, and stops. Concretely, **the following are deliberately absent**:

- Type inference. Nothing decides that `"42"` is an integer. A CSV field is a
  string; turning it into something else is the caller's business and depends on
  semantics `csvkit` does not have.
- Header handling beyond *reporting*. `looks_like_header` answers a question; it
  does not restructure the table into records.
- Streaming and incremental parsing. The API is `String -> Result[Table,
  CsvError]`. A streaming API is a different, larger design, and shipping a
  half-considered one would be worse than shipping none.
- Query, join, sort, group. Those are table operations, not CSV operations.
- Sniffing the delimiter from the data. Guessing is how a CSV pipeline silently
  reads the wrong column. The dialect is either the default or passed
  explicitly.

The result is a small surface — 12 functions, 6 types, 3 aliases — in which
every name means what it says. Reviewing a small surface is possible; reviewing
a broad one means sampling it.

## 2. Two error models, because there are two kinds of problem

A CSV document can fail in two genuinely different ways, and conflating them is
the most common design mistake in CSV libraries.

**The document is not well-formed.** An opening quote is never closed, or there
is text after a closing quote. There is no reasonable interpretation, so there
is no result. These are `CsvError`, returned as `Err`.

**The document is well-formed but structurally odd.** A row has four fields
where the header had three. A line is blank. Two columns share a name. RFC 4180
explicitly permits variable field counts, and real-world files routinely contain
blank lines, so none of these is a parse failure. Rejecting them would make the
library refuse files that every other tool accepts.

These are `Issue`, collected by `diagnose` into a `Report`, and returned
alongside a perfectly usable `Table`. The caller decides whether a ragged row is
fatal; the library does not decide for them.

The split shows up in the API as two functions with different shapes:

```
parse    : String -> Result[Table, CsvError]     // may fail
diagnose : Table  -> Report                      // cannot fail
```

and in the CLI as two exit codes, `1` for a CSV error and `2` for a usage or
I/O error. A malformed file and a mistyped command are different failures and
should be distinguishable without parsing stderr text.

## 3. The parser is a single forward pass

The grammar is regular, so the parser is a loop with an index rather than a
recursive-descent parser. Two consequences are worth stating because they are
load-bearing rather than incidental:

- **No recursion on input structure.** Deeply nested or very long input cannot
  exhaust the call stack. CSV has no nesting, but the property still matters
  when reasoning about malformed input.
- **Errors are a slot, not a control-flow jump.** The loop is

  ```
  let mut fail : CsvError? = None
  while i < total && fail is None { ... }
  ```

  rather than a `return` from inside the loop. This was not the first attempt.
  The initial version used `return`, which in this MoonBit version cannot appear
  inside a `while` body in that position, and `nobreak` — the construct that
  would express "stop the loop, keep going after it" — does not exist. The slot
  is the way to say it that both compiles and reads clearly: the loop condition
  itself states that scanning stops at the first error.

## 4. Separators: permissive by default, strict on request

RFC 4180 says records are separated by CRLF. Real files use bare LF constantly,
and files that have passed through a Windows toolchain can contain bare CR.

The default dialect (`Dialect::rfc4180()`) therefore accepts **CRLF, bare LF,
and bare CR** as record separators. `Dialect::strict_crlf()` and
`Dialect::strict_lf()` accept exactly one form and raise `UnexpectedLineBreak`
on anything else.

The default is not laziness. A library that rejects bare LF is unusable in
practice, and a library that silently accepts bare CR without saying so is
hiding a decision. Making it a *dialect* means the permissiveness is visible in
the API — a caller reading `Dialect::rfc4180()` can find out what it accepts —
and a caller who needs the strict reading can ask for it by name.

## 5. The lone-empty-field problem

This one is genuinely subtle and is the most interesting decision in the
repository.

Consider the table with a single empty field:

```
[[""]]
```

Serialised naively, this is the empty document. Under the dialect's rules, the
empty document contains **zero** records — correctly, since CSV has no
representation for "one row with one empty field" other than a delimiter or a
quote. So `parse(serialize([[""]]))` would return `[]`, not `[[""]]`, and
round-tripping would silently lose a row.

The fix: when a record consists of exactly one field and that field is empty,
the writer emits `""` — an explicitly quoted empty string.

```
serialize([[""]])  ==  "\"\"\r\n"
parse("\"\"\r\n")  ==  Ok([[""]])          // the row survives
```

This is not an invention. It is the only encoding in which the grammar can
distinguish the two cases, and it is why `RFC 4180 errata 5664` matters for a
writer as well as a reader.

The bug was found by the round-trip test over the differential corpus, which
reported 91 failures. Every one of them was this case. It is preserved as an
explicit test — *"writer: lone empty field is quoted to survive round-trip"* —
because a future refactor of the quoting predicate could reintroduce it
silently, and the failure mode (a dropped row) is invisible in most pipelines.

## 6. External evidence, not self-consistency

A library's own test suite can only demonstrate self-consistency: that what we
write, we can read, and that our parser obeys the grammar as we understand it. A
private dialect that is internally coherent passes such a suite perfectly.

The differential corpus addresses this directly. Python's `csv` module is an
independent implementation of the same specification, deployed on an enormous
number of systems. `tools/gen_differential.py` writes 1078 CSV documents with
Python's writer and records the tables Python's reader recovers from them.
`csvkit` must agree, field for field, on all of them.

The agreement cannot be explained by our own assumptions, because the
expectations were produced by code we did not write. That is what makes this
test the strongest evidence in the repository.

Three details make it trustworthy rather than decorative:

- **Reproducible.** The seed is fixed at `20260929` and generation order is
  fixed, so two runs are byte-identical. CI regenerates and fails if the tree
  changed, catching a corpus edited by hand.
- **Not a no-op if it breaks.** The loader skips unparseable lines rather than
  aborting, so the test asserts a minimum case count (1000) — otherwise a
  corrupt file would make the suite pass vacuously.
- **No Python at test time.** The corpus is checked in; `moon test` needs only
  the MoonBit toolchain. Python is required only to regenerate.

### The bare-CR exclusion, stated plainly

Python's writer will emit a lone `\r` inside an unquoted field. RFC 4180 does
not permit that, and `csvkit` rejects it as `UnexpectedLineBreak`. Rather than
relax the parser to match a reference more permissive than the specification,
such documents are excluded from the corpus, and the generator reports the count
on every run so the exclusion is never silent.

## 7. The base64 corpus format

`testdata/differential.tsv` stores `base64(document) TAB base64(json(records))`.

Base64 is doing real work twice over. First, the corpus file can never be
mistaken for CSV by a tool scanning the repository. Second, embedded CR and LF
survive any checkout setting — a corpus containing raw CRLF would be corrupted
by `core.autocrlf`, by a Windows editor, or by a `.gitattributes` rule nobody
remembered to add, and the corruption would look like a parser bug.

## 8. `InvalidUtf8` was removed

An early draft of `CsvError` had a fifth variant, `InvalidUtf8`. It was removed
because it is unreachable: a `String` in MoonBit is always valid UTF-8, so the
parser can never observe invalid encoding. An error variant that no input can
construct is a maintenance hazard — it invites callers to write handling code
that can never run, and it advertises a guarantee the types already provide.

Removing it also removed the two `impl Show` blocks that existed only to render
it, which is why `types.mbt` is shorter than it was.

## 9. Deprecated APIs are fixed, not silenced

`moon check --deny-warn` runs in CI. The codebase is currently warning-free, and
getting there meant fixing the causes rather than suppressing them:
`StringBuilder::new()` became `StringBuilder()`, `StringView::to_string()`
became `to_owned()`, `@sys.get_cli_args()` became `@env.args()` with the
corresponding package import, and `Show` was dropped in favour of `Debug` in
test output.

Denying warnings rather than tolerating them matters for a project reviewed by
strangers: a build with warnings is a build where the reviewer has to decide,
warning by warning, whether each one is the author's oversight or a deliberate
exception. A clean build removes that question.
