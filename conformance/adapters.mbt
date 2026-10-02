// Adapters that expose ecosystem CSV implementations as corpus candidates.
//
// Each adapter is deliberately thin, and each one carries a comment naming the
// shape mismatch it has to absorb. That is the point: a conformance report is
// only worth reading if the layer between "library X" and "the corpus" is
// explicit. An adapter that quietly normalises too much turns a real
// disagreement into a pass; one that normalises too little turns an API design
// choice into a false accusation. Both are worse than no report.

// ---------------------------------------------------------------------------
// maria/csv_parser
// ---------------------------------------------------------------------------

///|
/// `maria/csv_parser` — "a robust RFC 4180 compliant CSV parser with support for
/// custom delimiters, quoted fields, and serialization".
///
/// Shape: already `Array[Array[String]]`, so nothing has to be reconciled.
/// `parse` is used rather than `parse_with_config` so the library is measured in
/// its own default configuration, which its README presents as RFC 4180.
enum Maria {
  Maria
}

///|
impl @csvkit.CsvCandidate for Maria with fn label(_self) {
  "maria/csv_parser"
}

///|
impl @csvkit.CsvCandidate for Maria with fn parse(_self, input) {
  match @maria.parse(input) {
    Ok(rows) => Ok(rows)
    Err(e) => Err(maria_message(e))
  }
}

///|
/// Render a `maria/csv_parser` error. The enum carries positions but no
/// preformatted text, so the message is assembled here rather than pulled from
/// a `Show` instance whose format is not this report's business.
fn maria_message(e : @maria.CsvError) -> String {
  match e {
    @maria.CsvError::UnexpectedEof(line, column) =>
      "unexpected end of input at \{line}:\{column}"
    @maria.CsvError::UnterminatedQuote(line, column) =>
      "unterminated quoted field at \{line}:\{column}"
    @maria.CsvError::InvalidQuoteEscape(line, column) =>
      "invalid quote escape at \{line}:\{column}"
  }
}

// ---------------------------------------------------------------------------
// CJR-zhang/mbitsv
// ---------------------------------------------------------------------------

///|
/// `CJR-zhang/mbitsv` — a delimited-text data quality toolkit, measured in its
/// own default configuration.
///
/// Shape mismatch, and the one that matters most in this report: `mbitsv`
/// models a document as a `Table` with the header row held separately from the
/// body (`Table { header : Array[String], rows : Array[Array[String]] }`), and
/// its `csv_config()` sets `has_header: true`. Comparing `table.rows` directly
/// against the corpus would report every document as missing its first record —
/// a false accusation about an API modelling choice, not a parsing defect.
///
/// The adapter therefore requests `has_header: false` while keeping every other
/// field of the library's own `csv_config()`. No row is dropped or fabricated.
///
/// Two of the remaining fields are *policies* rather than grammar. `csv_config()`
/// documents itself as "RFC-4180 style CSV defaults", but it also sets
/// `skip_empty_lines: true` and `strict_columns: true`:
///
/// - `skip_empty_lines` discards records that look blank, so `""`, ` ` and `,`
///   come back as zero records where the reference reports one.
/// - `strict_columns` refuses a document whose records have differing field
///   counts. RFC 4180 permits that (it says records *should* have the same
///   number of fields, and a conforming reader still has to cope), and the
///   reference accepts it, so every ragged document in the corpus is rejected.
///
/// Keeping those two at the library's defaults is the honest choice for a
/// candidate named "default config": it measures what a caller who follows the
/// README actually gets. `MbitsvGrammarOnly` below measures the same library
/// with the policies switched off, so the report can separate "the parser
/// disagrees" from "the default policy disagrees". Conflating the two would be
/// the single most misleading thing this report could do.
enum Mbitsv {
  Mbitsv
}

///|
impl @csvkit.CsvCandidate for Mbitsv with fn label(_self) {
  "CJR-zhang/mbitsv (default config)"
}

///|
impl @csvkit.CsvCandidate for Mbitsv with fn parse(_self, input) {
  let config = { ..@mbitsv.csv_config(), has_header: false, }
  match @mbitsv.parse_with(input, config) {
    Ok(table) => Ok(table.rows)
    Err(e) => Err(mbitsv_message(e))
  }
}

///|
/// `CJR-zhang/mbitsv` with its ragged-record policy disabled.
///
/// `csv_config()` sets `strict_columns: true`, which makes the parser reject any
/// document whose records have differing field counts — 334 of the corpus's
/// 1078 documents. RFC 4180 permits ragged records (it says records *should*
/// have the same number of fields, and a conforming reader still has to cope),
/// and the reference accepts them, so this variant isolates how much of the
/// disagreement above is that one policy.
///
/// Only `strict_columns` is relaxed, and `has_header` is turned off so the
/// corpus's headerless documents are not mistaken for header-plus-body.
///
/// `skip_empty_lines` is deliberately *left at its default*, and that is not
/// caution — it is load-bearing. Switching it off makes the same library emit a
/// spurious trailing empty record for every document that ends in `\r\n`, so
/// every corpus document diverges and the measurement says nothing about the
/// parser. A configuration nobody would choose is not a fair baseline to
/// publish next to a real one, so the report keeps the policy that the library
/// relies on for its record model and varies only the policy that is genuinely
/// separable.
enum MbitsvLenientColumns {
  MbitsvLenientColumns
}

///|
impl @csvkit.CsvCandidate for MbitsvLenientColumns with fn label(_self) {
  "CJR-zhang/mbitsv (strict_columns off)"
}

///|
impl @csvkit.CsvCandidate for MbitsvLenientColumns with fn parse(_self, input) {
  let config = {
    ..@mbitsv.csv_config(),
    has_header: false,
    strict_columns: false,
  }
  match @mbitsv.parse_with(input, config) {
    Ok(table) => Ok(table.rows)
    Err(e) => Err(mbitsv_message(e))
  }
}

///|
/// Render an `mbitsv` parse error from its public fields.
fn mbitsv_message(e : @mbitsv.ParseError) -> String {
  "\{e.code}: \{e.message} at \{e.line}:\{e.column}"
}

// ---------------------------------------------------------------------------
// csvkit itself
// ---------------------------------------------------------------------------

///|
/// This library, put through the same harness as everyone else.
///
/// Included so the report is not a one-sided audit: the tool that measures the
/// ecosystem also measures its author's implementation, using the identical
/// code path.
enum Csvkit {
  Csvkit
}

///|
impl @csvkit.CsvCandidate for Csvkit with fn label(_self) {
  "BenPaoBaMingWangXing/csvkit"
}

///|
impl @csvkit.CsvCandidate for Csvkit with fn parse(_self, input) {
  match @csvkit.parse(input) {
    Ok(rows) => Ok(rows)
    Err(e) => Err(e.to_message())
  }
}
