// csvkit — writer and round-trip tests.
//
// The round-trip property `parse(serialize(t)) == t` is the writer's contract.
// These tests pin the individual quoting decisions that make it hold, so that a
// regression names the rule it broke rather than only reporting a diff.

///|
/// A field containing the delimiter must be quoted, otherwise the reader would
/// split it in two.
test "writer: delimits with a comma inside a field are quoted" {
  inspect(@csvkit.serialize([["a,b", "c"]]), content="\"a,b\",c\r\n")
}

///|
/// A quote inside a field is doubled, and the field is quoted.
test "writer: quotes are doubled" {
  inspect(
    @csvkit.serialize([["say \"hi\"", "x"]]),
    content="\"say \"\"hi\"\"\",x\r\n",
  )
}

///|
/// Embedded CRLF forces quoting; without it the reader would see two records.
test "writer: embedded newline forces quoting" {
  inspect(@csvkit.serialize([["a\nb", "c"]]), content="\"a\nb\",c\r\n")
}

///|
/// Leading and trailing whitespace is quoted defensively, because many readers
/// trim it and the round-trip would then lose characters.
test "writer: leading and trailing spaces are quoted" {
  inspect(@csvkit.serialize([[" x", "y "]]), content="\" x\",\"y \"\r\n")
}

///|
/// Interior spaces are not special and must not be quoted, or the output would
/// differ from every other CSV writer for no reason.
test "writer: interior spaces are not quoted" {
  inspect(@csvkit.serialize([["a b", "c"]]), content="a b,c\r\n")
}

///|
/// The empty field in the middle of a record needs no quotes: the delimiters
/// already define it unambiguously.
test "writer: empty middle field is not quoted" {
  inspect(@csvkit.serialize([["a", "", "c"]]), content="a,,c\r\n")
}

///|
/// A record holding a single empty field *must* be quoted. Writing a bare line
/// break would parse back as zero records, so `""` is the only form that
/// round-trips — the one place where the writer deliberately deviates from
/// "quote only when necessary".
test "writer: lone empty field is quoted to survive round-trip" {
  inspect(@csvkit.serialize([[""]]), content="\"\"\r\n")
  inspect(
    @csvkit.parse(@csvkit.serialize([[""]])).unwrap().length(),
    content="1",
  )
  inspect(@csvkit.parse(@csvkit.serialize([[""]])).unwrap()[0][0], content="")
}

///|
/// The LF dialect writes LF-only line endings.
test "writer: LF dialect uses LF endings" {
  inspect(
    @csvkit.serialize_with([["a", "b"]], @csvkit.Dialect::strict_lf()),
    content="a,b\n",
  )
}

///|
/// The semicolon dialect quotes the delimiter it actually uses, not a comma.
test "writer: semicolon dialect quotes semicolons" {
  inspect(
    @csvkit.serialize_with([["a;b", "c"]], @csvkit.Dialect::semicolon()),
    content="\"a;b\";c\r\n",
  )
}

///|
/// A hand-rolled renderer for failure messages. `Table` is an alias for
/// `Array[Array[String]]`, and a type alias cannot carry `derive(Debug)`, so
/// the round-trip loop needs its own helper to avoid `Show` (which would
/// truncate long values).
fn render(table : @csvkit.Table) -> String {
  let parts : Array[String] = []
  for row in table {
    let cells : Array[String] = []
    for cell in row {
      cells.push("\"" + cell + "\"")
    }
    parts.push("[" + cells.join(", ") + "]")
  }
  "[" + parts.join(", ") + "]"
}

///|
/// Round-trip over hand-written tables covering every quoting rule at once.
test "writer: round-trips hand-written tables" {
  let tables : Array[@csvkit.Table] = [
    [["a", "b", "c"]],
    [["a", "", "c"]],
    [["", ""]],
    [["a,b", "c\"d"]],
    [["line1\nline2", "x"]],
    [["\r\n", "y"]],
    [[" é中 ", "z"]],
    [["a"], ["b"], ["c"]],
    [[""]],
    [["", ""], ["", ""]],
  ]
  let mut i = 0
  while i < tables.length() {
    let original = tables[i]
    let back = @csvkit.parse(@csvkit.serialize(original)).unwrap()
    let mut ok = back.length() == original.length()
    if ok {
      let mut r = 0
      while r < original.length() {
        if back[r].length() != original[r].length() {
          ok = false
        } else {
          let mut c = 0
          while c < original[r].length() {
            if back[r][c] != original[r][c] {
              ok = false
            }
            c = c + 1
          }
        }
        r = r + 1
      }
    }
    if !ok {
      println("round-trip failed at table \{i}: \{render(original)}")
    }
    inspect(ok, content="true")
    i = i + 1
  }
}

///|
/// `needs_quoting` is the public predicate behind the writer's decisions, so its
/// answers are pinned individually.
test "writer: needs_quoting predicate" {
  let d = @csvkit.Dialect::rfc4180()
  inspect(@csvkit.needs_quoting("plain", d), content="false")
  inspect(@csvkit.needs_quoting("a,b", d), content="true")
  inspect(@csvkit.needs_quoting("a\"b", d), content="true")
  inspect(@csvkit.needs_quoting("a\nb", d), content="true")
  inspect(@csvkit.needs_quoting("a\rb", d), content="true")
  inspect(@csvkit.needs_quoting(" a", d), content="true")
  inspect(@csvkit.needs_quoting("a ", d), content="true")
  inspect(@csvkit.needs_quoting("", d), content="false")
  inspect(@csvkit.needs_quoting("a\tb", d), content="false")
}

///|
/// An empty table serializes to the empty string, and an empty string parses
/// back to an empty table.
test "writer: empty table is stable" {
  inspect(@csvkit.serialize([]), content="")
  inspect(@csvkit.parse("").unwrap().length(), content="0")
}

///|
/// `serialize_row` writes one record with no trailing line ending.
test "writer: serialize_row omits the line ending" {
  inspect(
    @csvkit.serialize_row(["a", "b,c"], @csvkit.Dialect::rfc4180()),
    content="a,\"b,c\"",
  )
}
