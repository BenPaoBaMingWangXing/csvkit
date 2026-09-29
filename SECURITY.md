# Security Policy

## Scope

`csvkit` is a **CSV parser and serialiser**. It is a data-format library, not a
security boundary. It makes no network requests, spawns no subprocesses, reads
no environment variables, and — apart from the CLI reading the file named on the
command line — touches no filesystem paths. The library package declares no
dependencies at all.

That limits the attack surface to one thing: **crafted input causing a crash,
a hang, or incorrect output.**

### What counts as a vulnerability here

- An input document that makes the parser panic rather than return `Err`.
- An input document that makes the parser loop forever or consume unbounded
  memory.
- A document for which `parse(serialize(t))` silently produces something other
  than `t`, where `t` contains only values the writer claims to support.
- A document that parses to a table differing from what a conforming RFC 4180
  implementation produces, in a way that could corrupt a downstream pipeline.

### What does not

- Input that is rejected with a `CsvError`. Rejecting malformed input is the
  documented behaviour, not a defect.
- The documented limitations in the README, including the handling of a bare CR
  in an unquoted field.
- Any issue that requires the caller to already be running untrusted code.

## Supported versions

The project is at `0.1.0` and has no released maintenance branches. Fixes land
on `main`; there is no backport policy yet.

| Version | Supported |
| --- | --- |
| 0.1.x | Yes |

## Reporting

Open a private security advisory through GitHub:

<https://github.com/BenPaoBaMingWangXing/csvkit/security/advisories/new>

Please include:

- The exact input that triggers the problem. Because the input is the whole
  attack surface, a base64-encoded document is ideal — it survives mail clients
  and issue trackers without corruption.
- What you observed, and what you expected.
- The output of `moon version --all`, plus your OS and backend
  (`wasm`, `wasm-gc`, `js`, or `native`).

If the input is large, reduce it first. A minimal reproducing document is far
more useful than a large one.

## Disclosure

Please allow time for a fix before publishing. This is a small project, so
rather than promise a fixed number of days, the acknowledgement below is what
you can rely on: an issue will be acknowledged, and whether it is in scope and
whether a fix is planned will both be stated.

## Design notes relevant to robustness

Two properties are deliberate and worth knowing when assessing a report:

**The parser is a single forward pass with an index, not a recursive descent.**
There is no recursion on input structure, so a deeply nested or very long
document cannot exhaust the call stack. Nesting is not a concept CSV has, but
the property matters for reasoning about malformed input.

**Input is scanned as `Array[Char]`, and `String` in MoonBit is always valid
UTF-8.** There is consequently no invalid-UTF-8 error variant: it would be
unreachable. Earlier drafts carried an `InvalidUtf8` case, and it was removed
once it became clear the type system already guarantees the condition — an
error variant that can never be constructed is a maintenance hazard, since it
invites callers to write handling code that can never run.

**Error reporting does not itself allocate proportionally to the input.** All
four error variants carry a `Position` and, for `FieldCountMismatch`, three
integers. A malformed multi-megabyte document produces a constant-size error,
not one that quotes the offending field.
