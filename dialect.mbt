// csvkit — dialects for the CSV variants that are *not* RFC 4180.
//
// These exist because the two most common real-world deviations are mechanical
// to express but tedious to get right: semicolon-delimited files (European
// locales, where the comma is the decimal separator) and tab-delimited files
// (TSV, `text/tab-separated-values`). Both keep the RFC 4180 quoting rules
// verbatim; only the delimiter changes.

///|
/// European-style CSV: `;` delimiter, `"` quoting, LF-tolerant line endings.
/// Used by many accounting exports and spreadsheet "save as CSV" on locales
/// where the comma is the decimal separator.
pub fn Dialect::semicolon() -> Dialect {
  { separator: Any, delimiter: ';', quote: '"', strip_bom: false, }
}

///|
/// Tab-separated values. Quoting rules are inherited from RFC 4180, which is
/// what makes this safe for fields containing tabs or newlines.
pub fn Dialect::tab() -> Dialect {
  { separator: Any, delimiter: '\t', quote: '"', strip_bom: false, }
}

///|
/// Strict RFC 4180 with CRLF as the only accepted separator.
///
/// This is the dialect to use when checking conformance of a file that claims
/// to be strictly RFC 4180, and the natural counterpart of `serialize`, which
/// always emits CRLF.
pub fn Dialect::strict_crlf() -> Dialect {
  { separator: Crlf, delimiter: ',', quote: '"', strip_bom: false, }
}

///|
/// Strict RFC 4180 with LF as the only accepted separator.
pub fn Dialect::strict_lf() -> Dialect {
  { separator: Lf, delimiter: ',', quote: '"', strip_bom: false, }
}

///|
/// The RFC 4180 dialect plus BOM stripping. Recommended when consuming files
/// produced by Excel on Windows, which prepends `EF BB BF`.
pub fn Dialect::excel() -> Dialect {
  { separator: Any, delimiter: ',', quote: '"', strip_bom: true, }
}

///|
/// Returns the same dialect with a different delimiter, for callers that need a
/// variant not covered by the named constructors.
pub fn Dialect::with_delimiter(self : Dialect, d : Char) -> Dialect {
  {
    separator: self.separator,
    delimiter: d,
    quote: self.quote,
    strip_bom: self.strip_bom,
  }
}

///|
/// Returns the same dialect with BOM stripping enabled or disabled.
pub fn Dialect::with_bom_stripping(self : Dialect, on : Bool) -> Dialect {
  {
    separator: self.separator,
    delimiter: self.delimiter,
    quote: self.quote,
    strip_bom: on,
  }
}
