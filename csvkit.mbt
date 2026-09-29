// csvkit — RFC 4180 CSV parsing and serialization for MoonBit.
//
// This package implements the format described by RFC 4180 (Common Format and
// MIME Type for CSV Files, Y. Shafranovich, October 2005). The public API is
// deliberately small and total: every entry point either returns a value or an
// explicit `CsvError`, it never raises and never silently loses input.
//
// Normative references:
//   RFC 4180  https://www.rfc-editor.org/rfc/rfc4180
//   RFC 4180 errata 5664 (clarifies the quoted-field grammar)
//
// The library is split across a few files so that each concern can be reviewed
// on its own: `types.mbt` (the error model), `parser.mbt`, `writer.mbt`,
// `dialect.mbt` (the non-RFC escapes real-world producers emit) and
// `diagnostics.mbt` (structural checks that are useful but not part of parsing).

///|
/// csvkit: RFC 4180 CSV parsing and serialization.
///
/// ```
/// let rows = @csvkit.parse("a,b\n1,2\n").unwrap()
/// inspect(rows[1][1], content="2")
/// ```
pub fn version() -> String {
  "0.1.0"
}
