# RFC 4180 conformance matrix

Every normative statement in RFC 4180, and where `csvkit` implements and pins
it. The point of this table is auditability: a reviewer should be able to check
a specific clause without reading the whole parser, and should be able to see
which clauses are deliberately *not* enforced.

The specification used is
[RFC 4180](https://www.rfc-editor.org/rfc/rfc4180) plus
[errata 5664](https://www.rfc-editor.org/errata/eid5664), which corrects the
`escaped` production to accept a doubled quote inside a quoted field.

Test names below are the literal test names; `moon test` reports them verbatim,
so each row can be checked by running the suite and reading the output.

---

## Grammar

| # | Rule | Status | Test |
| --- | --- | --- | --- |
| 1 | Each record is on a separate line, delimited by CRLF | Enforced | `rfc4180: two records, three fields` |
| 2a | The last record **may or may not** have a trailing CRLF | Enforced | `rfc4180: optional trailing CRLF` |
| 2b | An empty document contains no records | Enforced | `rfc4180: empty input yields no records` |
| 3 | There may be an optional header line, with the same format as other records | Not enforced | See "Not enforced", item B |
| 4 | Within the header and each record, fields are separated by commas | Enforced | `rfc4180: two records, three fields` |
| 5a | Fields **may or may not** be enclosed in double quotes | Enforced | `rfc4180: doubled quote encodes one quote` |
| 5b | The quote may not be inside an unquoted field — see item 7 | Enforced | `rfc4180: quote after unquoted text is an error` |
| 6a | A quoted field starts and ends with a double quote | Enforced | `rfc4180: quoted field containing a comma` |
| 6b | A double quote appearing inside a quoted field must be escaped by doubling it | Enforced | `rfc4180: doubled quote encodes one quote` |
| 6c | An escaped quote is the only place a quote appears inside a quoted field | Enforced | `rfc4180: text after closing quote is an error` |
| 7a | A field containing a comma must be enclosed in double quotes | Enforced (writer) | `writer: delimits with a comma inside a field are quoted` |
| 7b | A field containing CRLF must be enclosed in double quotes | Enforced (writer) | `writer: embedded newline forces quoting` |
| 7c | A field containing a double quote must be enclosed in double quotes | Enforced (writer) | `writer: quotes are doubled` |
| 7d | Comma / CRLF / double quote inside a quoted field are literal data | Enforced | `rfc4180: quoted field containing CRLF`, `rfc4180: quoted field containing bare LF` |
| 8 | Spaces are part of the field and must not be ignored | Enforced | `writer: leading and trailing spaces are quoted`, `writer: interior spaces are not quoted` |

## Empty fields

RFC 4180 has no explicit clause for empty fields; they follow from the
delimiter rule and from the fact that a quoted field may be empty.

| Case | Test |
| --- | --- |
| Empty fields between delimiters | `rfc4180: empty fields` |
| A quoted empty field is one empty field, not zero | `rfc4180: quoted empty field is one empty field` |
| A record of one empty field survives round-tripping | `writer: lone empty field is quoted to survive round-trip` |

The last row is the subtle case. Under the grammar, `\r\n` alone is *not* a
record, so the only encoding of "one row, one empty field" is the quoted `""`.
Naive serialisation would silently drop the row. See `docs/design.md` §5.

## Record separators

The default dialect accepts CRLF, bare LF and bare CR. This is a deliberate,
visible dialect choice rather than hidden leniency — see "Not enforced", item E.

| Case | Test |
| --- | --- |
| Bare LF accepted by default | `rfc4180: bare LF line endings accepted by default` |
| Bare CR accepted by default | `rfc4180: lone CR line endings accepted by default` |
| All three mixed in one document | `rfc4180: mixed CRLF, LF and CR in one file` |
| Strict CRLF dialect accepts CRLF | `strict Crlf dialect accepts CRLF` |
| Strict CRLF dialect rejects bare LF | `strict Crlf dialect rejects bare LF` |
| Strict LF dialect rejects CRLF | `strict Lf dialect rejects CRLF` |

## Errors

| Case | Test |
| --- | --- |
| Text after a closing quote | `rfc4180: text after closing quote is an error` |
| A quote appearing after unquoted text | `rfc4180: quote after unquoted text is an error` |
| An unterminated quoted field | `rfc4180: unterminated quoted field` |
| A space before an opening quote | `space before opening quote is an error` |
| The reported position points at the offending character | `error position points at the opening quote` |
| Columns are counted in characters, not bytes | `error column counts characters not bytes` |

The last row pins a real class of bug. `StringView` indexes are byte offsets
while `find` reports character positions; mixing the two silently truncates any
line containing multibyte text. The corpus loader had exactly this defect, so
both the loader and the error positions are covered.

## Encoding

RFC 4180 discusses character sets informally and recommends nothing binding.
`csvkit` operates on UTF-8 by construction, because a MoonBit `String` is always
valid UTF-8.

| Case | Test |
| --- | --- |
| Multibyte UTF-8 survives | `utf8 multibyte content survives` |
| A BOM is preserved by default | `bom is preserved by default` |
| The Excel dialect strips a BOM | `bom stripped by excel dialect` |
| A BOM-only document yields no records when stripped | `bom-only input with stripping yields no records` |

## Alternative dialects

| Case | Test |
| --- | --- |
| Semicolon delimiter | `semicolon dialect splits on semicolons` |
| Semicolon delimiter is quoted by the writer | `writer: semicolon dialect quotes semicolons` |
| Tab delimiter | `tab dialect splits on tabs` |
| Quoted tabs are preserved | `tab dialect keeps quoted tabs` |
| LF line endings from the writer | `writer: LF dialect uses LF endings` |

## Differential conformance

`testdata/differential.tsv` holds 1078 documents written by Python 3.13's `csv`
module, together with the tables Python recovers from them. Both directions are
pinned:

| Property | Test |
| --- | --- |
| `csvkit` parses each document exactly as Python does | `differential: csvkit agrees with Python csv on the full corpus` |
| `parse(serialize(t)) == t` for every corpus table | `differential: serialize/parse round-trips every corpus table` |

This is the project's **external** consistency evidence. It is the only test
whose expectations were produced by code we did not write, which is what makes
it stronger than the rest of the suite. See `docs/design.md` §6.

The corpus floor is asserted at 1000 cases. Because the loader skips
unparseable lines instead of aborting, a corrupt file would otherwise turn the
test into a vacuous pass.

---

## Remaining tests

Cases that do not map to a single clause but pin behaviour worth naming
explicitly.

| Area | Test |
| --- | --- |
| Writer: an empty field in the middle needs no quotes | `writer: empty middle field is not quoted` |
| Writer: an empty table serialises to the empty string | `writer: empty table is stable` |
| Writer: the quoting predicate, case by case | `writer: needs_quoting predicate` |
| Writer: `serialize_row` emits no line ending | `writer: serialize_row omits the line ending` |
| Writer: round-trip over hand-written tables | `writer: round-trips hand-written tables` |
| Diagnostics: a clean table reports nothing | `diagnostics: clean table has no issues` |
| Diagnostics: repeated cells inside one record | `diagnostics: duplicate cells within a record are reported` |
| Diagnostics: two or more empty cells are not duplicates | `diagnostics: equal empty cells are not duplicates` |
| Diagnostics: field counting | `diagnostics: count_fields_per_record` |
| Diagnostics: rendering | `diagnostics: to_lines renders issues` |

Note the distinction in the third and fourth diagnostics rows: a duplicate is a
*repeated non-empty* value. Two empty cells are not duplicates of each other,
because an empty cell is the absence of a value, and reporting several blanks as
"duplicated" would be noise.

---

## Not enforced, and why

### A. Blank lines

RFC 4180 does not describe blank lines. Real files contain them constantly,
usually as a cosmetic artefact of how the file was produced.

A blank line is treated as **not a record** — it produces no row, not an empty
one. `diagnose` reports it as `Issue::BlankLine`, so the caller sees it and
decides. Rejecting the document would make the library unusable on files every
other tool reads without complaint.

Pinned by `diagnostics: empty table` and `diagnostics: ragged row is reported`.

### B. Header handling

RFC 4180 §2 item 3 says a header line *may* be present. It gives no rule for
deciding whether one is, because the format carries no such marker — a header is
convention, not syntax.

`csvkit` therefore does not guess. `looks_like_header` offers a conservative
heuristic, and both the README and the function's doc comment say plainly that
it is a heuristic rather than a decision procedure. `diagnose` reports header
*problems* — an empty name, a duplicated name — as issues, never as errors.

Pinned by:

- `diagnostics: numeric first record is not a header`
- `diagnostics: named first record is a header`
- `diagnostics: single record is not treated as a header`
- `diagnostics: duplicate header names are reported`
- `diagnostics: empty header cell is reported`

### C. Field count consistency

RFC 4180 says every record "should contain the same number of fields". *Should*,
not *must*.

A variable field count parses fine, so `parse` accepts it. `check_field_counts`
returns `Err(FieldCountMismatch(..))` and `diagnose` reports `Issue::Ragged` for
callers who want the stricter reading. Both are available; neither is forced.

Pinned by `diagnostics: ragged input still parses`,
`diagnostics: ragged row is reported`,
`diagnostics: check_field_counts passes uniform tables through`,
`diagnostics: check_field_counts attributes the first bad line`,
`diagnostics: reference width comes from the first record`, and
`diagnostics: parse_strict rejects ragged input`.

### D. Encoding

Covered above. There is no `InvalidUtf8` error variant because the type system
makes the condition unrepresentable — an error variant no input can construct is
a maintenance hazard. See `docs/design.md` §8.

### E. Bare CR as a record separator

Strictly, records end with CRLF. In practice files contain bare LF, and files
that have passed through a Windows toolchain can contain bare CR.

The default dialect accepts all three; the `strict_*` dialects accept exactly
one form and raise `UnexpectedLineBreak` otherwise. Permissiveness is a visible
dialect choice, not hidden behaviour.

The consequence for the differential corpus: Python's writer emits a lone `\r`
inside unquoted fields, which the specification does not permit and `csvkit`
rejects. Rather than relax the parser to match a reference more permissive than
the specification, such documents are excluded from the corpus, and
`tools/gen_differential.py` reports the count on every run so the exclusion is
never silent.
