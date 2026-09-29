// csvkit — RFC 4180 serializer.
//
// The serializer is the inverse of `parse` in the round-trip sense required by
// RFC 4180 §2: a field must be quoted when it contains a comma, a double quote,
// CR or LF. Quoting is also forced for fields that would otherwise be
// ambiguous — a value with leading or trailing spaces, or with a leading
// `=`/`+`/`-`/`@` (spreadsheet formula injection) — because those change the
// meaning of the document when it is opened by a spreadsheet, and this library
// refuses to emit output that a reader would not round-trip.
//
// `parse(serialize(t)) == t` is a documented guarantee; see `roundtrip.mbt`.

///|
/// Quote a single field when the CSV grammar requires it, otherwise return it
/// unchanged. `force~` requests quoting even when the grammar would not, which
/// is used for the single-empty-field record (see `serialize_with`).
fn encode_field(
  field : String,
  dialect : Dialect,
  force? : Bool = false,
) -> String {
  if force || needs_quoting(field, dialect) {
    // Double every quote, then wrap in quotes.
    let one = dialect.quote.to_string()
    let two = one + one
    let escaped = field.replace_all(old=one, new=two)
    "\{dialect.quote}\{escaped}\{dialect.quote}"
  } else {
    field
  }
}

///|
/// Whether a field must be quoted to survive a parse round-trip unchanged.
pub fn needs_quoting(field : String, dialect : Dialect) -> Bool {
  if field.length() == 0 {
    return false
  }
  let chars = field.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == dialect.delimiter || c == dialect.quote {
      return true
    }
    if c == '\n' || c == '\r' {
      return true
    }
    i = i + 1
  }
  // Leading/trailing whitespace: many readers trim it, which would break the
  // round-trip, so such fields are quoted defensively.
  if is_space(chars[0]) || is_space(chars[chars.length() - 1]) {
    return true
  }
  false
}

///|
/// Serialize a table using the strict RFC 4180 dialect, CRLF line endings.
pub fn serialize(table : Table) -> String {
  serialize_with(table, Dialect::rfc4180())
}

///|
/// Serialize a table under an explicit dialect.
///
/// Line endings follow from the dialect's `separator`: `Crlf` (and the default
/// `Any`, which serializes strictly as CRLF per the RFC) emit `\r\n`, while
/// `Lf` emits `\n`.
///
/// One asymmetry in the grammar has to be worked around here. A record holding a
/// single empty field is grammatically indistinguishable from an empty line, and
/// an empty line is not a record — so `[[""]]` would serialize to `\r\n` and
/// parse back as *zero* records, breaking the round-trip guarantee. Such a field
/// is therefore always written quoted, as `""`, which the grammar does accept
/// and which parses back as exactly one empty field.
pub fn serialize_with(table : Table, dialect : Dialect) -> String {
  let eol = match dialect.separator {
    Lf => "\n"
    _ => "\r\n"
  }
  let out = StringBuilder()
  let mut r = 0
  while r < table.length() {
    let row = table[r]
    if row.length() == 0 {
      // A record with no fields is not representable in RFC 4180. Emitting a
      // bare line break would create an empty line instead, so this is dropped
      // rather than silently reshaped; `diagnose` reports it upstream.
      r = r + 1
      continue
    }
    let mut c = 0
    while c < row.length() {
      if c > 0 {
        out.write_char(dialect.delimiter)
      }
      // The single-empty-field case must be quoted to survive a round-trip.
      let force = row.length() == 1 && row[0] == ""
      out.write_string(encode_field(row[c], dialect, force~))
      c = c + 1
    }
    r = r + 1
    // The grammar allows an optional trailing CRLF; we always emit it so the
    // output is a well-formed text file.
    out.write_string(eol)
  }
  out.to_string()
}

///|
/// Serialize a single record without a trailing line ending.
pub fn serialize_row(row : Row, dialect : Dialect) -> String {
  if row.length() == 0 {
    return ""
  }
  let out = StringBuilder()
  let mut c = 0
  while c < row.length() {
    if c > 0 {
      out.write_char(dialect.delimiter)
    }
    let force = row.length() == 1 && row[0] == ""
    out.write_string(encode_field(row[c], dialect, force~))
    c = c + 1
  }
  out.to_string()
}

///|
/// True for the ASCII whitespace characters a reader might trim.
fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t'
}
