// csvkit — RFC 4180 conformance tests.
//
// Every case below is traced to a specific line of RFC 4180 §2 or to errata
// 5664, and the expectation is the grammar's, not the implementation's. Where
// the RFC is silent or permissive (bare LF, BOM) the test documents the choice
// explicitly rather than asserting "whatever the code does".
//
// Note on `content=`: `inspect` renders arrays via `Debug`, which prints string
// elements without quotes (`[a, b]`, not `["a", "b"]`). Field-level assertions
// below compare single strings, which avoids depending on that rendering.

///|
/// RFC 4180 §2: `aaa,bbb,ccc CRLF zzz,yyy,xxx CRLF` are two records of three
/// fields each.
test "rfc4180: two records, three fields" {
  let rows = parse("aaa,bbb,ccc\r\nzzz,yyy,xxx\r\n").unwrap()
  inspect(rows.length(), content="2")
  inspect(rows[0].length(), content="3")
  inspect(rows[0][0], content="aaa")
  inspect(rows[0][1], content="bbb")
  inspect(rows[0][2], content="ccc")
  inspect(rows[1][0], content="zzz")
  inspect(rows[1][1], content="yyy")
  inspect(rows[1][2], content="xxx")
}

///|
/// RFC 4180 §2, the trailing CRLF in `file` is optional.
test "rfc4180: optional trailing CRLF" {
  inspect(parse("aaa,bbb,ccc\r\nzzz,yyy,xxx").unwrap().length(), content="2")
  inspect(
    parse("aaa,bbb,ccc\r\nzzz,yyy,xxx\r\n").unwrap().length(),
    content="2",
  )
}

///|
/// An empty input has no records at all, and a bare line break is not a record:
/// the grammar requires a record to contain at least one field.
test "rfc4180: empty input yields no records" {
  inspect(parse("").unwrap().length(), content="0")
  inspect(parse("\r\n").unwrap().length(), content="0")
  inspect(parse("\n").unwrap().length(), content="0")
  inspect(parse("\r").unwrap().length(), content="0")
}

///|
/// RFC 4180 §2 field with embedded comma must be quoted.
test "rfc4180: quoted field containing a comma" {
  let rows = parse("aaa,\"b,bb\",ccc\r\n").unwrap()
  inspect(rows[0].length(), content="3")
  inspect(rows[0][0], content="aaa")
  inspect(rows[0][1], content="b,bb")
  inspect(rows[0][2], content="ccc")
}

///|
/// RFC 4180 §2: a doubled quote inside a quoted field denotes one literal
/// quote.
test "rfc4180: doubled quote encodes one quote" {
  let rows = parse("\"She said \"\"hi\"\"\",bbb\r\n").unwrap()
  inspect(rows[0][0], content="She said \"hi\"")
  inspect(rows[0][1], content="bbb")
}

///|
/// RFC 4180 §2: escaped fields may contain CR and LF. That is the whole reason
/// a conforming parser cannot split on newlines.
test "rfc4180: quoted field containing CRLF" {
  let rows = parse("aaa,\"line1\r\nline2\",ccc\r\n").unwrap()
  inspect(rows.length(), content="1")
  inspect(rows[0][1], content="line1\r\nline2")
}

///|
/// Same rule with a bare LF inside the quoted field.
test "rfc4180: quoted field containing bare LF" {
  let rows = parse("aaa,\"line1\nline2\",ccc\n").unwrap()
  inspect(rows.length(), content="1")
  inspect(rows[0][1], content="line1\nline2")
}

///|
/// RFC 4180 §2 `non-escaped = *TEXTDATA`: an empty field is legal, both via
/// `,,` and via a trailing comma.
test "rfc4180: empty fields" {
  let r1 = parse("a,b,\r\n").unwrap()[0]
  inspect(r1.length(), content="3")
  inspect(r1[2], content="")
  let r2 = parse("a,,c\r\n").unwrap()[0]
  inspect(r2.length(), content="3")
  inspect(r2[1], content="")
  let r3 = parse(",,\r\n").unwrap()[0]
  inspect(r3.length(), content="3")
  inspect(r3[0], content="")
  inspect(r3[1], content="")
  inspect(r3[2], content="")
}

///|
/// A quoted empty field is one empty field. Compare with `"\r\n"`, which has no
/// record at all — the distinction the parser preserves.
test "rfc4180: quoted empty field is one empty field" {
  let rows = parse("\"\"\r\n").unwrap()
  inspect(rows.length(), content="1")
  inspect(rows[0].length(), content="1")
  inspect(rows[0][0], content="")
}

///|
/// RFC 4180 §2 permits a bare LF as the line break. `RecordSeparator::Any`
/// accepts it.
test "rfc4180: bare LF line endings accepted by default" {
  let rows = parse("a,b\nc,d\n").unwrap()
  inspect(rows.length(), content="2")
  inspect(rows[0][0], content="a")
  inspect(rows[0][1], content="b")
  inspect(rows[1][0], content="c")
  inspect(rows[1][1], content="d")
}

///|
/// And a lone CR, which old Mac software still emits.
test "rfc4180: lone CR line endings accepted by default" {
  let rows = parse("a,b\rc,d\r").unwrap()
  inspect(rows.length(), content="2")
  inspect(rows[0][1], content="b")
  inspect(rows[1][0], content="c")
}

///|
/// Mixed endings in one file must not produce phantom fields.
test "rfc4180: mixed CRLF, LF and CR in one file" {
  let rows = parse("a,b\r\nc,d\ne,f\rg,h").unwrap()
  inspect(rows.length(), content="4")
  inspect(rows[2][0], content="e")
  inspect(rows[3][1], content="h")
}

///|
/// The strict dialect rejects what the permissive one accepts, and says why.
test "strict Crlf dialect rejects bare LF" {
  match parse_with("a,b\nc,d\n", Dialect::strict_crlf()) {
    Err(UnexpectedLineBreak(_, _)) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "strict Lf dialect rejects CRLF" {
  match parse_with("a,b\r\nc,d\r\n", Dialect::strict_lf()) {
    Err(UnexpectedLineBreak(_, _)) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
/// The strict CRLF dialect accepts a conforming file.
test "strict Crlf dialect accepts CRLF" {
  let rows = parse_with("a,b\r\nc,d\r\n", Dialect::strict_crlf()).unwrap()
  inspect(rows.length(), content="2")
  inspect(rows[1][1], content="d")
}

///|
/// RFC 4180 errata 5664 makes it explicit that only DQUOTE terminates an
/// escaped field, so `"abc"def` is malformed.
test "rfc4180: text after closing quote is an error" {
  match parse("\"abc\"def\r\n") {
    Err(UnescapedQuoteInQuotedField(_)) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
/// A field that starts unquoted may not pick up a quote partway through.
test "rfc4180: quote after unquoted text is an error" {
  match parse("abc\"def\r\n") {
    Err(UnescapedQuoteInQuotedField(_)) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
/// An unterminated quoted field is a hard error, not a silent truncation.
test "rfc4180: unterminated quoted field" {
  match parse("aaa,\"bbb\r\n") {
    Err(UnterminatedQuotedField(_)) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
/// Error positions must be actionable: the unterminated field is reported where
/// the quote was opened, not where the input ran out.
test "error position points at the opening quote" {
  match parse("ok,fine\r\nbad,\"unclosed") {
    Err(UnterminatedQuotedField(pos)) => {
      inspect(pos.line, content="2")
      inspect(pos.column, content="5")
    }
    _ => inspect("unexpected success", content="unreachable")
  }
}

///|
/// A BOM is not stripped by default, so the first header cell keeps it — a
/// deliberate choice, since dropping bytes silently is worse than surfacing it.
test "bom is preserved by default" {
  let rows = parse("\u{FEFF}a,b\r\n").unwrap()
  inspect(rows[0][0], content="\u{FEFF}a")
}

///|
/// ...and stripped on request via the Excel dialect.
test "bom stripped by excel dialect" {
  let rows = parse_with("\u{FEFF}a,b\r\n", Dialect::excel()).unwrap()
  inspect(rows[0].length(), content="2")
  inspect(rows[0][0], content="a")
  inspect(rows[0][1], content="b")
}

///|
/// A BOM with no following content is not a record.
test "bom-only input with stripping yields no records" {
  inspect(
    parse_with("\u{FEFF}", Dialect::excel()).unwrap().length(),
    content="0",
  )
}

///|
/// Multi-byte characters must not be split or double-counted.
test "utf8 multibyte content survives" {
  let rows = parse("姓名,城市\r\n安枢,深圳\r\n").unwrap()
  inspect(rows[0][0], content="姓名")
  inspect(rows[0][1], content="城市")
  inspect(rows[1][0], content="安枢")
  inspect(rows[1][1], content="深圳")
}

///|
/// Column positions are counted in characters, not bytes, so a multibyte prefix
/// does not inflate the reported column.
test "error column counts characters not bytes" {
  match parse("姓名,\"unclosed") {
    Err(UnterminatedQuotedField(pos)) => inspect(pos.column, content="4")
    _ => inspect("unexpected", content="unreachable")
  }
}

///|
/// A space before the opening quote makes the field unquoted per the grammar,
/// and the quote then appears mid-field, which is an error.
test "space before opening quote is an error" {
  match parse(" \"a\",b\r\n") {
    Err(UnescapedQuoteInQuotedField(_)) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
/// Semicolon and tab dialects keep RFC 4180 quoting rules; only the delimiter
/// changes.
test "semicolon dialect splits on semicolons" {
  let rows = parse_with("a;\"b;b\";c\r\n", Dialect::semicolon()).unwrap()
  inspect(rows[0].length(), content="3")
  inspect(rows[0][1], content="b;b")
}

///|
test "tab dialect splits on tabs" {
  let rows = parse_with("a\tb\tc\r\n", Dialect::tab()).unwrap()
  inspect(rows[0].length(), content="3")
  inspect(rows[0][1], content="b")
}

///|
/// A tab inside a quoted field survives under the tab dialect.
test "tab dialect keeps quoted tabs" {
  let rows = parse_with("a\t\"b\tb\"\r\n", Dialect::tab()).unwrap()
  inspect(rows[0][1], content="b\tb")
}
