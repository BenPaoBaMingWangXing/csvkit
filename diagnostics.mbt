// csvkit — structural diagnostics.
//
// These helpers answer questions that come up when auditing a CSV file, but
// which RFC 4180 does not define. They are kept out of the parse path so that
// parsing stays a single, predictable operation, and so that each check can be
// tested in isolation. Every report is a plain data structure, not a formatted
// string, so callers can decide how to present it.

///|
/// What is wrong with a header cell.
pub enum HeaderProblem {
  /// The header cell is empty.
  Empty
  /// The header cell repeats an earlier name.
  Duplicated(String)
} derive(Eq, Debug)

// The promotion is deliberate: `Eq` and `Debug` are part of the public
// surface of this type, so it is declared here rather than left implicit.

///|
pub extend HeaderProblem with Eq::{not_equal, equal}

///|
pub extend HeaderProblem with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// One irregularity found in a document.
///
/// All fields are positional so the constructors can be used both to build
/// issues and to pattern-match them.
pub enum Issue {
  /// A record whose field count differs from the reference record.
  Ragged(Int, Int, Int) // line, expected, actual
  /// A record with no content at all.
  BlankLine(Int) // line
  /// A record containing the same non-empty value twice.
  Duplicate(Int, Int) // line, column
  /// A problem with the header record.
  HeaderProblem(Int, HeaderProblem) // column, kind
} derive(Eq, Debug)

// The promotion is deliberate: `Eq` and `Debug` are part of the public
// surface of this type, so it is declared here rather than left implicit.

///|
pub extend Issue with Eq::{not_equal, equal}

///|
pub extend Issue with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A structural report over a parsed table.
pub struct Report {
  /// Total records including the header.
  records : Int
  /// Number of fields in the reference record, or 0 for an empty table.
  columns : Int
  /// Irregularities in file order.
  issues : Array[Issue]
} derive(Eq, Debug)

// The promotion is deliberate: `Eq` and `Debug` are part of the public
// surface of this type, so it is declared here rather than left implicit.

///|
pub extend Report with Eq::{not_equal, equal}

///|
pub extend Report with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Whether the report found no irregularities.
pub fn Report::is_clean(self : Report) -> Bool {
  self.issues.length() == 0
}

///|
/// Inspect a table for ragged rows, blank lines, duplicated cells and header
/// problems.
///
/// The first record is treated as a header. Raising such issues is a caller-side
/// policy decision: RFC 4180 explicitly permits ragged files, so `csvkit` never
/// rejects them during parsing.
pub fn diagnose(table : Table) -> Report {
  if table.length() == 0 {
    return { records: 0, columns: 0, issues: [], }
  }
  let columns = table[0].length()
  let issues : Array[Issue] = []
  if columns == 0 {
    issues.push(BlankLine(1))
  }
  let mut col = 0
  while col < columns {
    let name = table[0][col]
    if name == "" {
      issues.push(HeaderProblem(col, Empty))
    } else {
      let mut prev = 0
      let mut dup = false
      while prev < col {
        if table[0][prev] == name {
          dup = true
        }
        prev = prev + 1
      }
      if dup {
        issues.push(HeaderProblem(col, Duplicated(name)))
      }
    }
    col = col + 1
  }
  let mut r = 0
  while r < table.length() {
    let row = table[r]
    let line = r + 1
    if row.length() != columns {
      issues.push(Ragged(line, columns, row.length()))
    }
    if row.length() == 1 && row[0] == "" {
      issues.push(BlankLine(line))
    }
    // Duplicate values *within* a record: two equal cells carry no more
    // information than one and usually signal a writer bug.
    let mut a = 0
    while a < row.length() {
      let mut b = a + 1
      let mut is_dup = false
      while b < row.length() {
        if row[a] == row[b] && row[a] != "" {
          is_dup = true
        }
        b = b + 1
      }
      if is_dup {
        issues.push(Duplicate(line, a))
      }
      a = a + 1
    }
    r = r + 1
  }
  { records: table.length(), columns, issues, }
}

///|
/// Render a report as one line per issue, for CLI display.
pub fn Report::to_lines(self : Report) -> Array[String] {
  let out : Array[String] = []
  let mut i = 0
  while i < self.issues.length() {
    out.push(
      match self.issues[i] {
        Ragged(line, expected, actual) =>
          "line \{line}: ragged, expected \{expected} fields, found \{actual}"
        BlankLine(line) => "line \{line}: blank record"
        Duplicate(line, column) =>
          "line \{line}: duplicate value at column \{column + 1}"
        HeaderProblem(column, kind) =>
          match kind {
            Empty => "header column \{column + 1}: empty name"
            Duplicated(name) =>
              "header column \{column + 1}: duplicate name \"\{name}\""
          }
      },
    )
    i = i + 1
  }
  out
}

///|
/// RFC 4180 §2 recommends that consumers tolerate files without a header. This
/// helper makes that decision explicit and testable: it reports whether the
/// first record looks like names rather than data.
pub fn looks_like_header(table : Table) -> Bool {
  if table.length() < 2 {
    return false
  }
  let first = table[0]
  let mut any_numeric = false
  let mut i = 0
  while i < first.length() {
    if is_numeric(first[i]) {
      any_numeric = true
    }
    i = i + 1
  }
  !any_numeric
}

///|
/// True when a field is a plain decimal number, used only by
/// `looks_like_header`. Deliberately conservative: no exponents, no grouping.
fn is_numeric(field : String) -> Bool {
  if field.length() == 0 {
    return false
  }
  let chars = field.to_array()
  let mut i = 0
  let mut seen_digit = false
  let mut seen_dot = false
  if chars[0] == '-' || chars[0] == '+' {
    i = 1
  }
  while i < chars.length() {
    let c = chars[i]
    if c >= '0' && c <= '9' {
      seen_digit = true
    } else if c == '.' {
      if seen_dot {
        return false
      }
      seen_dot = true
    } else {
      return false
    }
    i = i + 1
  }
  seen_digit
}
