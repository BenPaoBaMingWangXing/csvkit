// csvkit — diagnostics tests.
//
// `diagnose` reports structure that RFC 4180 does not define. Because these are
// judgements rather than grammar violations, each test states which judgement is
// being made so the policy is visible, not buried in an implementation.

///|
/// A uniform table produces a clean report.
test "diagnostics: clean table has no issues" {
  let table = @csvkit.parse("a,b,c\r\n1,2,3\r\n4,5,6\r\n").unwrap()
  let report = @csvkit.diagnose(table)
  inspect(report.is_clean(), content="true")
  inspect(report.records, content="3")
  inspect(report.columns, content="3")
}

///|
/// A ragged row is reported with its line and both field counts.
test "diagnostics: ragged row is reported" {
  let table = @csvkit.parse("a,b,c\r\n1,2\r\n").unwrap()
  let report = @csvkit.diagnose(table)
  inspect(report.is_clean(), content="false")
  inspect(report.issues.length(), content="1")
  match report.issues[0] {
    Ragged(line, expected, actual) => {
      inspect(line, content="2")
      inspect(expected, content="3")
      inspect(actual, content="2")
    }
    _ => inspect("wrong issue kind", content="Ragged")
  }
}

///|
/// Raggedness is a reporting concern, not a parse error: the parse itself must
/// still succeed, because RFC 4180 permits it.
test "diagnostics: ragged input still parses" {
  inspect(@csvkit.parse("a,b,c\r\n1,2\r\n").unwrap().length(), content="2")
}

///|
/// Duplicate header names are reported per column. The header row is also just a
/// row, so the within-record duplicate check fires on it too; the test asserts
/// the header diagnostic is present among the rendered issues rather than
/// assuming it is the only one.
test "diagnostics: duplicate header names are reported" {
  let table = @csvkit.parse("id,name,id\r\n1,x,2\r\n").unwrap()
  let report = @csvkit.diagnose(table)
  inspect(report.is_clean(), content="false")
  let lines = report.to_lines()
  let mut found = false
  let mut i = 0
  while i < lines.length() {
    if lines[i].contains("duplicate name") {
      found = true
    }
    i = i + 1
  }
  inspect(found, content="true")
  // The duplicated column is the third, i.e. index 2, shown 1-based as 3.
  let mut found_column = false
  i = 0
  while i < lines.length() {
    if lines[i].contains("header column 3") {
      found_column = true
    }
    i = i + 1
  }
  inspect(found_column, content="true")
}

///|
/// An empty header cell is reported as such.
test "diagnostics: empty header cell is reported" {
  let table = @csvkit.parse("id,,name\r\n1,2,3\r\n").unwrap()
  let lines = @csvkit.diagnose(table).to_lines()
  let mut found = false
  let mut i = 0
  while i < lines.length() {
    if lines[i].contains("empty name") {
      found = true
    }
    i = i + 1
  }
  inspect(found, content="true")
}

///|
/// A record whose values repeat is flagged, because a duplicate cell usually
/// means the writer lost track of a column.
test "diagnostics: duplicate cells within a record are reported" {
  let table = @csvkit.parse("a,b\r\nx,x\r\n").unwrap()
  let report = @csvkit.diagnose(table)
  inspect(report.issues.length(), content="1")
  match report.issues[0] {
    Duplicate(line, column) => {
      inspect(line, content="2")
      inspect(column, content="0")
    }
    _ => inspect("wrong issue", content="Duplicate")
  }
}

///|
/// Empty cells are not duplicates: a row of blanks is legal and common.
test "diagnostics: equal empty cells are not duplicates" {
  let table = @csvkit.parse("a,b\r\n,\r\n").unwrap()
  inspect(@csvkit.diagnose(table).is_clean(), content="true")
}

///|
/// An empty table yields a zeroed report rather than a panic.
test "diagnostics: empty table" {
  let report = @csvkit.diagnose([])
  inspect(report.records, content="0")
  inspect(report.columns, content="0")
  inspect(report.is_clean(), content="true")
}

///|
/// `to_lines` renders one human-readable line per issue, 1-based for display.
test "diagnostics: to_lines renders issues" {
  let table = @csvkit.parse("a,b,c\r\n1,2\r\n").unwrap()
  let lines = @csvkit.diagnose(table).to_lines()
  inspect(lines.length(), content="1")
  inspect(lines[0].contains("line 2"), content="true")
  inspect(lines[0].contains("expected 3"), content="true")
  inspect(lines[0].contains("found 2"), content="true")
}

///|
/// A first record with numbers in it is data, not a header.
test "diagnostics: numeric first record is not a header" {
  let table = @csvkit.parse("1,2,3\r\n4,5,6\r\n").unwrap()
  inspect(@csvkit.looks_like_header(table), content="false")
}

///|
/// A first record of names is a header.
test "diagnostics: named first record is a header" {
  let table = @csvkit.parse("id,name\r\n1,2\r\n").unwrap()
  inspect(@csvkit.looks_like_header(table), content="true")
}

///|
/// A single record cannot establish whether it is a header.
test "diagnostics: single record is not treated as a header" {
  let table = @csvkit.parse("a,b,c\r\n").unwrap()
  inspect(@csvkit.looks_like_header(table), content="false")
}

///|
/// `check_field_counts` returns the table unchanged when it is uniform, so it
/// can be chained with further processing.
test "diagnostics: check_field_counts passes uniform tables through" {
  let table = @csvkit.parse("a,b\r\n1,2\r\n").unwrap()
  let checked = @csvkit.check_field_counts(table).unwrap()
  inspect(checked.length(), content="2")
  inspect(checked[1][1], content="2")
}

///|
/// ...and names the first offending line when it is not.
test "diagnostics: check_field_counts attributes the first bad line" {
  match
    @csvkit.check_field_counts(@csvkit.parse("a,b\r\n1,2\r\n3\r\n").unwrap()) {
    Err(@csvkit.FieldCountMismatch(line~, expected~, actual~)) => {
      inspect(line, content="3")
      inspect(expected, content="2")
      inspect(actual, content="1")
    }
    _ => inspect("expected mismatch", content="FieldCountMismatch")
  }
}

///|
/// `parse_strict` combines parsing with the field-count check.
test "diagnostics: parse_strict rejects ragged input" {
  match @csvkit.parse_strict("a,b\r\n1\r\n") {
    Err(@csvkit.FieldCountMismatch(..)) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
  inspect(@csvkit.parse_strict("a,b\r\n1,2\r\n").unwrap().length(), content="2")
}

///|
/// `count_fields_per_record` agrees with parsing, including for the records that
/// look empty.
test "diagnostics: count_fields_per_record" {
  let counts = @csvkit.count_fields_per_record("a,b,c\r\n1,2\r\n").unwrap()
  inspect(counts.length(), content="2")
  inspect(counts[0], content="3")
  inspect(counts[1], content="2")
}

///|
/// A non-empty table always has a non-zero column count, which `diagnose` uses
/// as the reference width.
test "diagnostics: reference width comes from the first record" {
  let report = @csvkit.diagnose(@csvkit.parse("x\r\nx,y\r\n").unwrap())
  inspect(report.columns, content="1")
  inspect(report.issues.length(), content="1")
}
