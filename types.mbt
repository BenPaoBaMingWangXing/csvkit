// csvkit — error model and public type aliases.
//
// The error type is intentionally flat and position-carrying: when a document is
// rejected, the caller gets a line/column and the offending context, so the
// message can be shown to a human without extra bookkeeping.

///|
/// A single CSV record: an ordered list of fields.
///
/// Fields are stored decoded, i.e. surrounding quotes have been removed and
/// doubled quotes have been collapsed. A field may be the empty string, which is
/// distinct from a record that is absent entirely.
pub type Row = Array[String]

///|
/// A parsed CSV document: records in file order.
pub type Table = Array[Row]

///|
/// Where in the input a problem was detected.
///
/// `line` and `column` are 1-based and refer to the *source* text, not to the
/// decoded field values. For errors that concern a whole record rather than a
/// byte, `column` points at the first character of the offending record.
pub struct Position {
  /// 1-based source line.
  line : Int
  /// 1-based source column, counted in Unicode scalar values.
  column : Int
} derive(Eq, Debug)

///|
/// Errors that prevent a document from being parsed or serialized.
///
/// Every variant carries enough context to produce an actionable message. The
/// parser never invents error states for input that RFC 4180 leaves undefined
/// (see `Dialect` for those); it only rejects input the grammar forbids.
pub enum CsvError {
  /// A quoted field was opened with the quote character but the input ended
  /// before the closing quote was seen. RFC 4180 requires escaped fields to be
  /// terminated.
  UnterminatedQuotedField(Position)
  /// A quote character appeared where the grammar does not allow it: after the
  /// first character of an unquoted field, or after the closing quote of a
  /// quoted field. UTF-16 text mis-decoded as UTF-8 hits this, which is why it
  /// is a hard error rather than a warning.
  UnescapedQuoteInQuotedField(Position)
  /// A line break that the selected `RecordSeparator` does not accept. Under a
  /// strict dialect a bare LF (or, for `Lf`, a CRLF) is not content — the
  /// grammar's TEXTDATA excludes CR and LF — so accepting it would silently
  /// change the document's meaning.
  UnexpectedLineBreak(Position, String)
  /// A record contained a different number of fields than the reference record.
  /// Only reported by the opt-in strict checks; `parse` is permissive because
  /// RFC 4180 does not mandate uniform field counts.
  FieldCountMismatch(line~ : Int, expected~ : Int, actual~ : Int)
} derive(Eq, Debug)

///|
/// Human-readable rendering of an error, suitable for CLI output.
///
/// This is the only place error wording is produced, so changing the phrasing
/// cannot affect anything that pattern-matches on `CsvError` itself.
pub fn CsvError::to_message(self : CsvError) -> String {
  match self {
    UnterminatedQuotedField(pos) =>
      "unterminated quoted field at line \{pos.line}, column \{pos.column}"
    UnescapedQuoteInQuotedField(pos) =>
      "unescaped quote inside quoted field at line \{pos.line}, column \{pos.column}"
    UnexpectedLineBreak(pos, expected) =>
      "line \{pos.line}: line break not allowed by the \{expected} separator, at column \{pos.column}"
    FieldCountMismatch(line~, expected~, actual~) =>
      "line \{line}: expected \{expected} fields, found \{actual}"
  }
}
