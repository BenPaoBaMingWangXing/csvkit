# Guide for agents and contributors

`csvkit` is an RFC 4180 CSV engine in MoonBit. This file records the conventions
that make the repository reviewable, so that a contribution — human or
automated — lands in the same shape as what is already here.

See <https://docs.moonbitlang.com> for the language and toolchain.

## Project structure

- Packages are per directory; each has a `moon.pkg` declaring its imports.
- `moon.mod` at the root holds module metadata.
- Test files end in `_test.mbt` (black-box) or `_wbtest.mbt` (white-box).
- The library package is the repository root. `cmd/main/` is the CLI.
- `tools/` holds Python scripts that generate checked-in artefacts.
- `docs/` holds prose that would bloat the README if inlined.

## The non-negotiable rules

**Name things after what they do.** Repository name, module name, package name,
README title and submission name must all read `csvkit`. A previous submission
of a related project was rejected partly over 名实相符, and the lesson is
enforced here.

**`moon check --deny-warn` must pass.** The codebase is warning-free. When you
hit a deprecation, fix the call site rather than suppressing the warning. See
`docs/design.md` §9 for the specific substitutions already applied.

**Never claim more than you verified.** If a feature is untested, say so or
leave it out. Documented behaviour must match actual behaviour; the README's
examples were checked by running them. Known limitations go in the README, in
the open, including the ones that are unflattering.

**State exclusions where they happen.** The differential corpus excludes
documents containing a bare CR. That exclusion is recorded in `tools/README.md`,
`NOTICE`, `docs/conformance.md` and the README, and the generator prints the
count on every run. A silent exclusion would be worse than no corpus.

**Test names must be real.** `docs/conformance.md` cites test names. If you
rename a test, update the documents that cite it — a conformance matrix pointing
at tests that do not exist is worse than no matrix.

## Workflow

```bash
moon check --deny-warn                 # type check, warnings fatal
moon build --target wasm               # build
moon test                              # 64 tests
moon fmt                               # format
moon info                              # refresh pkg.generated.mbti
```

Run `moon info && moon fmt` before committing. Inspect the `.mbti` diff: if it
is empty, the change did not alter the public surface, which is usually a good
sign for a refactor.

When a change affects test output snapshots, `moon test --update` refreshes them
— then **read the diff** rather than accepting it.

## Testing philosophy

Four suites, each answering a different question:

| File | Question |
|---|---|
| `conformance_test.mbt` | Does the grammar behave as RFC 4180 specifies? |
| `conformance_differential_test.mbt` | Does an independent implementation agree? |
| `writer_test.mbt` | Does the writer quote exactly when required, and round-trip? |
| `diagnostics_test.mbt` | Are structural reports correct and well-worded? |

A new behaviour needs a test in the suite that owns the claim. Adding a parser
feature without a conformance case leaves `docs/conformance.md` unable to cite
it, which means a reviewer cannot check it.

Prefer `assert_eq` / `inspect` on stable values. `inspect` renders `Debug`
output, so `Array[String]` prints as `[a, b]` with no quotes — assert on
individual fields or on length rather than on the rendered form of a container.

Note that a type alias cannot carry `derive(Debug)`. `Table` is
`Array[Array[String]]`, so it has no `debug()` method; where a failure message
needs to show a table, `writer_test.mbt` has a local `render` helper.

## Regenerating the corpus

```bash
python3 tools/gen_differential.py
moon test
```

The generator is deterministic (seed `20260929`). CI regenerates and fails if
the working tree changed, so never edit `testdata/differential.tsv` by hand.
See `tools/README.md`.

Running the tests needs only the MoonBit toolchain. Python is required only to
regenerate, because the corpus is checked in.

## Documentation style

Prose in this repository explains *why*, not *what*. The code says what. A
comment that restates the next line (`// increment i`) is noise; a comment that
records a rejected alternative, a bug that was found, or a specification
ambiguity is worth its length. `docs/design.md` is the model to follow.
