// csvkit — the RFC 4180 parser.
//
// Grammar implemented (RFC 4180 §2, with errata 5664):
//
//   file        = [header CRLF] record *(CRLF record) [CRLF]
//   header      = record
//   record      = field *(COMMA field)
//   field       = escaped / non-escaped
//   escaped     = DQUOTE *(TEXTDATA / COMMA / CR / LF / 2DQUOTE) DQUOTE
//   non-escaped = *TEXTDATA
//   COMMA       = %x2C                    CRLF = CR LF
//   DQUOTE      = %x22
//   TEXTDATA    = %x20-21 / %x23-2B / %x2D-7E
//
// Design notes
// ------------
// * The grammar makes CRLF the record separator, but the text also permits a
//   bare LF. Files in the wild use CRLF, LF and lone CR interchangeably, so the
//   default dialect accepts all three ("be liberal in what you accept") while
//   `RecordSeparator::Crlf` and `Lf` pin it down for conformance testing.
// * A BOM is not stripped by default. RFC 4180 is silent on it and dropping
//   bytes silently would contradict this library's "never lose input" stance.
//   Callers opt in via `Dialect::strip_bom`.
// * Parsing is one forward pass, no backtracking, O(n) in the input length.
//   Field values are accumulated as `String` segments and joined once, which
//   keeps the common case (short, unquoted fields) allocation-light.

///|
/// How records are separated in the input.
pub enum RecordSeparator {
  /// Accept `\r\n`, `\n` and `\r` (the default; matches real-world readers).
  Any
  /// Accept only `\r\n` (the strict RFC 4180 reading).
  Crlf
  /// Accept only `\n`.
  Lf
} derive(Eq, Debug)

///|
/// Knobs for the parts RFC 4180 leaves undefined or that producers implement
/// differently. Every option defaults to the strict RFC reading, so
/// `parse(s)` is exactly `parse_with(s, Dialect::rfc4180())`.
pub struct Dialect {
  /// How records are separated. Default: any of CRLF / LF / CR.
  separator : RecordSeparator
  /// Field delimiter. RFC 4180 fixes it to `,`; `;` and tab are common.
  delimiter : Char
  /// Quote character. RFC 4180 fixes it to `"`.
  quote : Char
  /// Strip a leading UTF-8 BOM before parsing. Default: false.
  strip_bom : Bool
} derive(Eq, Debug)

///|
/// The strict RFC 4180 dialect: comma delimiter, double-quote quoting, CRLF
/// preferred with bare LF/CR tolerated, no BOM stripping.
pub fn Dialect::rfc4180() -> Dialect {
  { separator: Any, delimiter: ',', quote: '"', strip_bom: false, }
}

///|
/// Parse a CSV document with the strict RFC 4180 dialect.
///
/// Trailing line break at end of file does not produce a spurious empty record,
/// per the grammar's optional trailing `[CRLF]`.
///
/// ```
/// let rows = @csvkit.parse("a,b\n1,2\n").unwrap()
/// inspect(rows.length(), content="2")
/// ```
pub fn parse(input : String) -> Result[Table, CsvError] {
  parse_with(input, Dialect::rfc4180())
}

///|
/// Parse a CSV document under an explicit dialect.
///
/// The scanner is a single forward pass. It is written as an explicit loop over
/// an index (`i`) rather than an iterator because the grammar needs two-byte
/// lookahead for `""` escapes and for CRLF, and it needs to report the exact
/// index at which a violation occurred.
pub fn parse_with(input : String, dialect : Dialect) -> Result[Table, CsvError] {
  let text = if dialect.strip_bom { strip_bom(input) } else { input }
  let chars = text.to_array()
  let total = chars.length()
  let rows : Table = []
  let row : Row = []
  let segments : Array[String] = []
  let mut in_quotes = false
  // Whether the field currently being scanned has any character at all. This
  // distinguishes `a,,c` (three fields, the middle one empty) from the trailing
  // separator in `a,b,`, and it is what makes a mid-field quote detectable.
  let mut field_has_content = false
  // Set once a field has been closed by its terminating quote, so that a
  // following character can be rejected instead of silently concatenated.
  let mut field_closed = false
  let mut quote_open_line = 1
  let mut quote_open_col = 1
  let mut line = 1
  let mut col = 1
  let mut i = 0
  // `fail` carries the first error out of the loop. Using a slot rather than
  // `return` keeps the loop a plain expression and avoids non-local control
  // flow, which matters because every `return` inside a `while` would otherwise
  // have to agree on the function's return type.
  let mut fail : CsvError? = None
  while i < total && fail is None {
    let c = chars[i]
    if in_quotes {
      if c == dialect.quote {
        if i + 1 < total && chars[i + 1] == dialect.quote {
          // Escaped quote inside a quoted field: one literal quote.
          segments.push(dialect.quote.to_string())
          i = i + 2
          col = col + 2
        } else {
          // Closing quote. The field is now closed: the next character must be
          // a delimiter or a record separator.
          in_quotes = false
          field_closed = true
          i = i + 1
          col = col + 1
        }
      } else {
        if is_line_break(c) {
          line = line + 1
          col = 1
        } else {
          col = col + 1
        }
        segments.push(c.to_string())
        i = i + 1
      }
    } else {
      let closed_then_garbage = field_closed &&
        c != dialect.delimiter &&
        !is_record_separator(c, chars, i, dialect.separator)
      if closed_then_garbage {
        // `"abc"def` is malformed under RFC 4180 errata 5664.
        fail = Some(UnescapedQuoteInQuotedField({ line, column: col, }))
      } else if c == dialect.quote {
        // A quote may only open a field. Once any character has been written to
        // the field, a quote is neither the first character nor an escape.
        if field_has_content {
          fail = Some(UnescapedQuoteInQuotedField({ line, column: col, }))
        } else {
          in_quotes = true
          field_has_content = true
          quote_open_line = line
          quote_open_col = col
          i = i + 1
          col = col + 1
        }
      } else if c == dialect.delimiter {
        row.push(segments.join(""))
        segments.clear()
        field_has_content = false
        field_closed = false
        i = i + 1
        col = col + 1
      } else if is_record_separator(c, chars, i, dialect.separator) {
        // Capture whether this record actually holds anything *before* closing
        // the pending field, because closing pushes an (empty) field into `row`
        // and would otherwise make every bare separator look like a record.
        let record_has_content = field_has_content || row.length() > 0
        if record_has_content {
          row.push(segments.join(""))
          rows.push(row.copy())
        }
        segments.clear()
        row.clear()
        field_has_content = false
        field_closed = false
        i = i + separator_len(c, chars, i, dialect.separator)
        line = line + 1
        col = 1
      } else if is_rejected_line_break(c, chars, i, dialect.separator) {
        // A line break this dialect does not accept. Reported rather than
        // folded into the field, so a strict conformance check fails loudly.
        fail = Some(
          UnexpectedLineBreak({ line, column: col, }, dialect.separator.name()),
        )
      } else {
        segments.push(c.to_string())
        field_has_content = true
        i = i + 1
        col = col + 1
      }
    }
  }
  match fail {
    Some(e) => Err(e)
    None => {
      if in_quotes {
        return Err(
          UnterminatedQuotedField({
            line: quote_open_line,
            column: quote_open_col,
          }),
        )
      }
      // Emit the final record: it exists when the file did not end on a
      // separator and the last record had content or an explicit delimiter.
      if field_has_content || row.length() > 0 {
        row.push(segments.join(""))
        rows.push(row.copy())
      }
      Ok(rows.copy())
    }
  }
}

///|
/// Parse a document and additionally require every record to have the same
/// number of fields as the first record (conventionally the header).
///
/// This is a validation layer, not part of parsing: a ragged file still parses,
/// and the caller opts in to the stricter check.
pub fn parse_strict(input : String) -> Result[Table, CsvError] {
  match parse(input) {
    Err(e) => Err(e)
    Ok(rows) => check_field_counts(rows)
  }
}

///|
/// Validate that all records share the first record's field count.
///
/// Returns the table unchanged when it is uniform, so it can be chained.
pub fn check_field_counts(rows : Table) -> Result[Table, CsvError] {
  if rows.length() == 0 {
    return Ok(rows)
  }
  let expected = rows[0].length()
  let mut i = 1
  while i < rows.length() {
    let actual = rows[i].length()
    if actual != expected {
      return Err(FieldCountMismatch(line=i + 1, expected~, actual~))
    }
    i = i + 1
  }
  Ok(rows)
}

///|
/// The number of fields in each record, in file order.
///
/// Shares the scanner rules with `parse`, so the two never disagree about what
/// counts as a field boundary; useful as a cheap structural pre-flight check.
pub fn count_fields_per_record(input : String) -> Result[Array[Int], CsvError] {
  match parse(input) {
    Err(e) => Err(e)
    Ok(rows) => Ok(rows.map(fn(r) { r.length() }))
  }
}

///|
/// True for either Unicode line break accepted inside a quoted field.
fn is_line_break(c : Char) -> Bool {
  c == '\n' || c == '\r'
}

///|
/// True when the character at `i` begins a record separator under `sep`.
fn is_record_separator(
  c : Char,
  chars : Array[Char],
  i : Int,
  sep : RecordSeparator,
) -> Bool {
  match sep {
    Any => c == '\n' || c == '\r'
    Lf => c == '\n'
    Crlf => c == '\r' && i + 1 < chars.length() && chars[i + 1] == '\n'
  }
}

///|
/// True when the character at `i` is a *line break but not one this dialect
/// accepts*. Such a character is a hard error under a strict dialect: it cannot
/// be content (the grammar's TEXTDATA excludes CR and LF), so accepting it would
/// mean silently changing the meaning of the document.
fn is_rejected_line_break(
  c : Char,
  chars : Array[Char],
  i : Int,
  sep : RecordSeparator,
) -> Bool {
  if c != '\n' && c != '\r' {
    return false
  }
  !is_record_separator(c, chars, i, sep)
}

///|
/// Human-readable name for a separator mode, used in error messages.
fn RecordSeparator::name(self : RecordSeparator) -> String {
  match self {
    Any => "CRLF, LF or CR"
    Crlf => "CRLF"
    Lf => "LF"
  }
}

///|
/// How many source characters the separator at `i` occupies.
fn separator_len(
  c : Char,
  chars : Array[Char],
  i : Int,
  sep : RecordSeparator,
) -> Int {
  match sep {
    Crlf => 2
    Lf => 1
    Any =>
      if c == '\r' && i + 1 < chars.length() && chars[i + 1] == '\n' {
        2
      } else {
        1
      }
  }
}

///|
/// True when `text` begins with the UTF-8 BOM.
fn starts_with_bom(text : String) -> Bool {
  text.has_prefix("\u{FEFF}")
}

///|
/// Remove a leading UTF-8 BOM if present, otherwise return the input unchanged.
fn strip_bom(text : String) -> String {
  if starts_with_bom(text) {
    text[1:].to_owned()
  } else {
    text
  }
}
