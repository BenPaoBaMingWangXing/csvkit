# Ecosystem survey and boundaries

Why this document exists
------------------------

An earlier version of this project's submission asserted, in one sentence, that
mooncakes.io had no complete RFC 4180 implementation. That sentence was wrong.

It was wrong for two reasons, and both are worth recording because they are
easy to repeat. First, the survey behind it searched for the *keyword* `csv`,
and a library called `mbitsv` — "delimited text", `sv` for separated values —
does not contain that string. Second, and worse, at least one implementation
that does contain it in its name, `maria/csv_parser`, describes itself in the
first line of its README as "a robust RFC 4180 compliant CSV parser with
support for custom delimiters, quoted fields, and serialization". Searching for
`csv` would have found it. The survey had not actually been run.

The project was reviewed and rejected for exactly this: *功能重叠，申报书未说明
扩展关系* — overlap with an existing project, with no boundary stated.

This document is the correction. It records what is actually in the ecosystem,
what this project does and does not share with it, and how the two relate. It is
kept in the repository rather than in the submission so that the survey can be
re-run and audited independently.

## Method, and what was actually searched

Conducted 2026-09-29, revised 2026-10-02. Four routes were used; the first alone
is what failed.

1. **Domain keywords** on mooncakes.io and the web: `csv`, `tsv`, `dsv`,
   `delimited`, `separated values`, `table`, `tabular`.
2. **Naming variants**, because a library's name need not contain the domain
   word: `sv`, `dsv`, `tsv`.
3. **Reverse lookup by capability and standard**, which is the route that
   actually works: `RFC 4180`, and the standard numbers of adjacent formats.
   Searching for the standard a project implements finds implementations whose
   names give no hint.
4. **Reading other submissions' own "related projects" sections.** Competing
   entries in the same ecosystem routinely name their neighbours — `mbitsv`'s
   `docs/PROVENANCE.md` lists the projects it is *not* related to, which is a
   map of the neighbourhood. This route found more than the other three
   combined.

## What is in the ecosystem

| Module | Author | License | Scope | Name contains `csv` |
| --- | --- | --- | --- | --- |
| `maria/csv_parser` | maria | Apache-2.0 | RFC 4180 parse and serialise, custom delimiters, quoted fields, errors with positions | yes |
| `sikadi123/moonbit-csv` | sikadi123 | Apache-2.0 | Parser, writer, CLI, browser playground, header validation, table views | yes |
| `CJR-zhang/mbitsv` | CJR-zhang | MIT | Delimited-text **data quality toolkit**: parsing plus dialect sniffing, schema inference and validation, table transforms and joins, keyed diff, quality gates, Markdown reports | no |

`mbitsv` is the one the review cited. Its first commit is 2026-08-02 and it was
submitted to the August term, with `docs/PROVENANCE.md` dated 2026-08-21 — a
month before this project's own submission. It was public and on mooncakes
throughout this project's development, which is what makes the earlier claim
indefensible rather than merely unfortunate.

## The overlap, stated plainly

There is real overlap on the parsing core, and hiding it would repeat the
original mistake:

| Capability | `maria/csv_parser` | `sikadi123/moonbit-csv` | `CJR-zhang/mbitsv` | `csvkit` |
| --- | --- | --- | --- | --- |
| Quoted fields, escaped quotes, embedded newlines | yes | yes | yes | yes |
| CRLF / LF | yes | yes | yes | yes |
| Write / serialise | yes | yes | yes | yes |
| Delimiter configuration | yes | yes | yes, plus auto-detect | yes |
| Errors carrying positions | yes | yes | yes | yes |
| CLI | — | yes | yes | yes |

On that list `csvkit` is not distinguished. Three implementations already cover
it, one of them with more downloads, and this project's own README described it
as an RFC 4180 parser — which is why the review's reading of the submission was
correct on the evidence the submission gave it.

## What is not overlapping

Two things, and only two.

**1. Verification rather than parsing.** The distinguishing asset was never the
parser; it is the *evidence*, and specifically the 1078-document corpus in
`testdata/differential.tsv`. Every document in it was produced by Python 3.13's
`csv.writer` and paired with the records `csv.reader` recovers from it. That
makes the corpus implementation-independent: it is not derived from this
library's behaviour, so agreeing with it is external evidence rather than a
self-test. `docs/conformance.md` maps each clause of RFC 4180 to the test that
pins it. Neither asset exists in the other three projects.

**2. A conformance layer other implementations can be measured with.** This is
the part that turns the overlap from a problem into the project's subject:
`conformance.mbt` plus the `conformance/` package decode the corpus, apply one
set of comparison rules, and measure *any* candidate implementation that
flattens its result to `Array[Array[String]]`. The results for the three
implementations above are published, unedited, in
[`docs/ecosystem-conformance.md`](ecosystem-conformance.md), and the report is
regenerated by `tools/conformance_report.py` rather than written by hand.

So the relationship is not "another CSV parser competing with the others". It is
a library that parses, plus a measurement instrument that the others can be
checked with — and, in the published report, have been.

## The published measurement, in one paragraph

Run against the 1078-document corpus: `csvkit` agrees with the reference on all
1078. `maria/csv_parser` agrees on 1077 and then **aborts** — its process dies —
on the one document containing a character outside the Basic Multilingual
Plane. `CJR-zhang/mbitsv` agrees on 633 in its default configuration; the
remaining disagreements decompose into two configuration policies and one
parser limit, separated in the report by re-running it with the ragged-record
policy disabled (877/1078). These are findings about the ecosystem, produced by
the instrument this project ships, and they are the reason the instrument is
worth having independently of the parser it was written beside.

## What this document does not claim

- It does not claim the survey is exhaustive. It claims it covers the four
  routes above on 2026-10-02, and that the three implementations listed are real
  and were measured.
- It does not claim `csvkit` is the only RFC 4180 implementation, or the best
  one. It claims the corpus and the instrument are not duplicated elsewhere.
- It does not treat the other implementations' results as defects on their part.
  `mbitsv` documents itself as a data quality toolkit and applies quality policy
  by default; the report separates that policy from its parser rather than
  scoring the policy as a failure. `maria/csv_parser`'s abort is a defect by any
  reading, and is reported as one because there is no configuration under which
  a parser should die.
