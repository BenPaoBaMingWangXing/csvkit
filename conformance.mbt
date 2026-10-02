// csvkit — the conformance layer.
//
// This file is the second half of what `csvkit` ships. The first half is an
// RFC 4180 implementation; this half is the machinery that decides whether an
// implementation *is* RFC 4180 — including implementations written by someone
// else.
//
// Why it lives in the library rather than in the test suite
// ---------------------------------------------------------
// The evidence in `testdata/differential.tsv` (1078 documents produced by
// Python 3.13's `csv` module, each paired with the records that module recovers
// from it) is useful to the whole ecosystem, not just to this repository. Any
// MoonBit CSV implementation can be pointed at the same corpus and told, case
// by case, where it disagrees with an independent reference.
//
// Keeping the decoding and comparison here means there is exactly one
// implementation of "what the corpus means". `conformance_differential_test.mbt`
// uses these functions to test this library, and the `conformance/` module uses
// the same functions to test other libraries. A framework that only worked on
// its own author's parser would be worthless, so the library's own test is
// deliberately routed through the same code path that is offered to others.
//
// Everything in this file is pure: no file I/O, no third-party dependencies.
// Reading the corpus from disk is the caller's job, because the library must
// stay buildable for every target while a candidate implementation may not be.

// ---------------------------------------------------------------------------
// Corpus decoding
// ---------------------------------------------------------------------------

///|
/// One conformance case: a document, and the records an independent reference
/// implementation recovers from it.
///
/// The reference here is Python's `csv.reader`. Because the corpus is generated
/// by writing a table with `csv.writer` and reading it back, every case in it
/// is a document that a conforming implementation must parse *successfully* —
/// the corpus contains no "expected to fail" cases by construction. A candidate
/// that rejects a corpus document is therefore diverging, not merely strict;
/// see `Verdict::Rejected`.
pub(all) struct CorpusCase {
  doc : String
  expected : Table
}

///|
/// A single case where a candidate implementation disagreed with the reference.
pub(all) struct Divergence {
  index : Int
  verdict : Verdict
  doc : String
  expected : Table
  /// The records the candidate produced. Empty when the candidate rejected the
  /// document outright; `message` then carries its explanation.
  actual : Table
  message : String
}

///|
/// How a candidate implementation handled one case.
pub enum Verdict {
  /// Produced exactly the reference records.
  Conform
  /// Parsed the document but produced different records.
  Divergent
  /// Refused a document that the reference parses. This is a divergence even
  /// though it is the "safe-looking" direction: RFC 4180 documents are
  /// unambiguous, so rejecting a legal one loses data.
  Rejected
} derive(Eq)

///|
/// The result of running a whole corpus through one candidate implementation.
pub(all) struct Summary {
  name : String
  total : Int
  conforming : Int
  divergent : Int
  rejected : Int
  /// Samples of *each* verdict kind, capped separately.
  ///
  /// Kept per kind rather than as one list of the first few failures: a
  /// candidate can fail in a single mode for hundreds of cases, and a report
  /// that only ever shows that mode tells a reader nothing about the others.
  /// Seeing the first few of each kind is what lets someone tell a systematic
  /// behaviour difference apart from a bug.
  divergent_samples : Array[Divergence]
  rejected_samples : Array[Divergence]
}

///|
/// Maximum number of samples kept per verdict kind.
const SAMPLE_LIMIT : Int = 6

///|
/// Decode one corpus line: `base64(document) TAB base64(json(records))`.
///
/// Both halves are base64 so the corpus file can never be mistaken for the CSV
/// it describes, and so embedded CR/LF survive any checkout setting.
///
/// Lines that are blank or do not split into two non-empty halves return `Err`
/// rather than silently becoming an empty case, so a truncated corpus fails
/// loudly instead of turning a conformance run into a no-op.
pub fn decode_corpus_line(line : String) -> Result[CorpusCase, String] {
  if line.length() == 0 {
    return Err("blank line")
  }
  match line.find("\t") {
    None => Err("no tab separator")
    Some(t) => {
      let doc_b64 = line[:t].to_owned()
      let exp_b64 = line[t + 1:].to_owned()
      if doc_b64.length() == 0 || exp_b64.length() == 0 {
        return Err("empty half")
      }
      match (base64_decode(doc_b64), base64_decode(exp_b64)) {
        (Ok(doc), Ok(exp)) => Ok({ doc, expected: parse_records(exp), })
        _ => Err("invalid base64")
      }
    }
  }
}

///|
/// Decode the compact records format used in the corpus: a JSON array of arrays
/// of strings, as produced by `json.dumps(..., ensure_ascii=False)`.
///
/// This reads that subset directly rather than pulling in a JSON package: the
/// producer and the consumer live in the same repository and the format is
/// pinned by `tools/gen_differential.py`, so a full parser would be more
/// surface area than the problem has. The escape sequences handled are the ones
/// `json.dumps` actually emits — `\"`, `\\`, `\n`, `\r`, `\t`, `\b`, `\f`,
/// `\/` and `\uXXXX`.
///
/// Note that the input is decoded as `String` but indexed by *character*, since
/// the corpus contains multibyte fields (`安枢`, `🙂`, `café`).
pub fn parse_records(source : String) -> Table {
  let out : Table = []
  let chars = source.to_array()
  let mut i = 0
  let mut row : Row = []
  let buf = StringBuilder()
  let mut in_str = false
  let mut in_row = false
  while i < chars.length() {
    let c = chars[i]
    if in_str {
      if c == '\\' && i + 1 < chars.length() {
        let e = chars[i + 1]
        match e {
          'n' => buf.write_char('\n')
          'r' => buf.write_char('\r')
          't' => buf.write_char('\t')
          'b' => buf.write_char('\u{0008}')
          'f' => buf.write_char('\u{000C}')
          '"' => buf.write_char('"')
          '\\' => buf.write_char('\\')
          '/' => buf.write_char('/')
          _ =>
            // \uXXXX
            if i + 5 < chars.length() {
              buf.write_char(hex4(chars, i + 2))
              i = i + 4
            }
        }
        i = i + 2
      } else if c == '"' {
        in_str = false
        row.push(buf.to_string())
        buf.reset()
        i = i + 1
      } else {
        buf.write_char(c)
        i = i + 1
      }
    } else if c == '"' {
      in_str = true
      i = i + 1
    } else if c == '[' {
      in_row = true
      row = []
      i = i + 1
    } else if c == ']' {
      if in_row {
        out.push(row.copy())
        row = []
        in_row = false
      }
      i = i + 1
    } else {
      i = i + 1
    }
  }
  out
}

///|
/// Read four hex digits as a Unicode scalar value.
fn hex4(chars : Array[Char], at : Int) -> Char {
  let mut v = 0
  let mut k = 0
  while k < 4 && at + k < chars.length() {
    let d = chars[at + k]
    let n = if d >= '0' && d <= '9' {
      d.to_int() - '0'.to_int()
    } else if d >= 'a' && d <= 'f' {
      d.to_int() - 'a'.to_int() + 10
    } else if d >= 'A' && d <= 'F' {
      d.to_int() - 'A'.to_int() + 10
    } else {
      0
    }
    v = v * 16 + n
    k = k + 1
  }
  v.unsafe_to_char()
}

///|
/// Standard base64 alphabet decoding, tolerating missing padding, followed by
/// UTF-8 decoding.
///
/// The decode is deliberately two steps. base64 yields *bytes*, and a byte is
/// not a character: building the result by widening each byte to a `Char` would
/// turn the UTF-8 sequence `C3 A9` (`é`) into the two characters `Ã©`, and
/// `F0 9F 99 82` (`🙂`) into four. That widening is silent — the corpus still
/// compares equal, because both sides of the comparison go through the same
/// decoder — so it does not show up as a failure anywhere. It shows up as this
/// library quietly testing a shifted representation instead of real text, which
/// is exactly the failure mode the differential corpus exists to prevent.
///
/// Malformed sequences become U+FFFD rather than aborting: the corpus is
/// generated from valid Python `str` values, so a malformed byte here would
/// mean the corpus file itself is damaged, and a replacement character makes
/// that visible in the comparison instead of taking the whole run down.
fn base64_decode(s : String) -> Result[String, String] {
  let chars = s.to_array()
  let bytes : Array[Int] = []
  let mut acc = 0
  let mut bits = 0
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '=' {
      i = chars.length()
    } else {
      match base64_value(c) {
        None => return Err("invalid base64 character")
        Some(v) => {
          acc = (acc << 6) | v
          bits = bits + 6
          if bits >= 8 {
            bits = bits - 8
            bytes.push((acc >> bits) & 0xFF)
            acc = acc & ((1 << bits) - 1)
          }
        }
      }
      i = i + 1
    }
  }
  Ok(utf8_decode(bytes))
}

///|
/// Decode UTF-8 bytes into a String.
///
/// Hand-written rather than delegated to a codec package because the library
/// keeps its dependency surface to `moonbitlang/core`, and because a decoder
/// this small is easier to read than to look up. Code points in the surrogate
/// range are rejected as malformed: they are not scalar values, and
/// `unsafe_to_char` is only safe for input that is.
fn utf8_decode(bytes : Array[Int]) -> String {
  let out = StringBuilder()
  let mut i = 0
  while i < bytes.length() {
    let b0 = bytes[i]
    if b0 < 0x80 {
      out.write_char(b0.unsafe_to_char())
      i = i + 1
    } else if b0 >= 0xC0 && b0 < 0xE0 && i + 1 < bytes.length() {
      push_code_point(out, ((b0 & 0x1F) << 6) | (bytes[i + 1] & 0x3F))
      i = i + 2
    } else if b0 >= 0xE0 && b0 < 0xF0 && i + 2 < bytes.length() {
      push_code_point(
        out,
        ((b0 & 0x0F) << 12) |
        ((bytes[i + 1] & 0x3F) << 6) |
        (bytes[i + 2] & 0x3F),
      )
      i = i + 3
    } else if b0 >= 0xF0 && i + 3 < bytes.length() {
      push_code_point(
        out,
        ((b0 & 0x07) << 18) |
        ((bytes[i + 1] & 0x3F) << 12) |
        ((bytes[i + 2] & 0x3F) << 6) |
        (bytes[i + 3] & 0x3F),
      )
      i = i + 4
    } else {
      out.write_char('\u{FFFD}')
      i = i + 1
    }
  }
  out.to_string()
}

///|
/// Append a decoded code point, substituting U+FFFD for anything that is not a
/// Unicode scalar value.
fn push_code_point(out : StringBuilder, cp : Int) -> Unit {
  if cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) {
    out.write_char('\u{FFFD}')
  } else {
    out.write_char(cp.unsafe_to_char())
  }
}

///|
/// Map a base64 alphabet character to its 6-bit value.
fn base64_value(c : Char) -> Int? {
  if c >= 'A' && c <= 'Z' {
    Some(c.to_int() - 'A'.to_int())
  } else if c >= 'a' && c <= 'z' {
    Some(c.to_int() - 'a'.to_int() + 26)
  } else if c >= '0' && c <= '9' {
    Some(c.to_int() - '0'.to_int() + 52)
  } else if c == '+' {
    Some(62)
  } else if c == '/' {
    Some(63)
  } else {
    None
  }
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

///|
/// Field-wise table equality.
///
/// Ragged tables are compared as-is: `[["a","b"],["c"]]` and `[["a","b"],["c","d"]]`
/// differ, and both are distinct from `[["a","b"],["c", ""]]`. Field counts are
/// deliberately *not* normalised — RFC 4180 permits ragged records, so padding
/// them before comparing would hide exactly the disagreement worth reporting.
pub fn tables_equal(a : Table, b : Table) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut r = 0
  while r < a.length() {
    if a[r].length() != b[r].length() {
      return false
    }
    let mut c = 0
    while c < a[r].length() {
      if a[r][c] != b[r][c] {
        return false
      }
      c = c + 1
    }
    r = r + 1
  }
  true
}

// ---------------------------------------------------------------------------
// Candidate implementations
// ---------------------------------------------------------------------------

///|
/// An implementation that can be put through the corpus.
///
/// Adapters are deliberately thin. Several libraries in the ecosystem model a
/// document as a header plus body rows, or hold a table rather than raw rows,
/// and those shapes must be flattened back to `Array[Array[String]]` *by the
/// adapter* — otherwise the framework would be reporting an API design
/// difference as a parsing defect, which would be worse than not reporting at
/// all. `conformance/` documents this per adapter.
///
/// Returning `Err` means the implementation refused the document. The message
/// is for humans reading the report; a conforming implementation should not
/// reach this branch for any corpus case, because the corpus only contains
/// documents an independent implementation produced and could read back.
pub(open) trait CsvCandidate {
  fn label(Self) -> String
  fn parse(Self, String) -> Result[Array[Array[String]], String]
}

///|
/// Run every case through one candidate and summarise what happened.
///
/// Cases are processed in corpus order so that samples are reproducible and the
/// first reported divergence is the first one in the file, which makes a failure
/// easy to locate by hand.
///
/// `on_case` is called with each case index immediately *before* the candidate
/// is asked to parse it. It exists for one reason: a candidate can panic, and a
/// panic is not catchable, so the only thing that survives an abort is what was
/// already written out. A caller that traces the index therefore learns which
/// document killed a candidate — otherwise a crash reports as "it died", which
/// is not a finding anybody can act on. The callback is called before the parse
/// rather than after so that the last line printed names the culprit and not
/// the case that came before it.
pub fn[T : CsvCandidate] run_corpus(
  candidate : T,
  cases : Array[CorpusCase],
  on_case : ((Int) -> Unit)?,
) -> Summary {
  let mut conforming = 0
  let mut divergent = 0
  let mut rejected = 0
  let divergent_samples : Array[Divergence] = []
  let rejected_samples : Array[Divergence] = []
  let mut i = 0
  while i < cases.length() {
    let c = cases[i]
    match on_case {
      Some(report) => report(i)
      None => ()
    }
    // The candidate is asked once per case. A second call purely to fill in a
    // sample would be wasteful and, for an implementation that is not a pure
    // function of its input, could disagree with the verdict being reported.
    let outcome = candidate.parse(c.doc)
    let verdict = match outcome {
      Ok(rows) =>
        if tables_equal(rows, c.expected) {
          Verdict::Conform
        } else {
          Verdict::Divergent
        }
      Err(_) => Verdict::Rejected
    }
    match verdict {
      Verdict::Conform => conforming = conforming + 1
      Verdict::Divergent => divergent = divergent + 1
      Verdict::Rejected => rejected = rejected + 1
    }
    let keep = match verdict {
      Verdict::Conform => false
      Verdict::Divergent => divergent_samples.length() < SAMPLE_LIMIT
      Verdict::Rejected => rejected_samples.length() < SAMPLE_LIMIT
    }
    if keep {
      let (actual, message) = match outcome {
        Ok(rows) => (rows, "")
        Err(m) => ([], m)
      }
      let sample = {
        index: i,
        verdict,
        doc: c.doc,
        expected: c.expected,
        actual,
        message,
      }
      match verdict {
        Verdict::Divergent => divergent_samples.push(sample)
        _ => rejected_samples.push(sample)
      }
    }
    i = i + 1
  }
  {
    name: candidate.label(),
    total: cases.length(),
    conforming,
    divergent,
    rejected,
    divergent_samples,
    rejected_samples,
  }
}

///|
/// True when every case agreed with the reference.
pub fn Summary::is_fully_conforming(self : Summary) -> Bool {
  self.divergent == 0 && self.rejected == 0
}

///|
/// The number of cases that disagreed, in either direction.
pub fn Summary::failures(self : Summary) -> Int {
  self.divergent + self.rejected
}

///|
/// The number of samples retained across both verdict kinds.
pub fn Summary::sample_count(self : Summary) -> Int {
  self.divergent_samples.length() + self.rejected_samples.length()
}

///|
/// A one-line human-readable result, of the form
/// `maria/csv_parser: 1078/1078 conform (0 divergent, 0 rejected)`.
pub fn Summary::to_line(self : Summary) -> String {
  let ok = self.total - self.failures()
  "\{self.name}: \{ok}/\{self.total} conform " +
  "(\{self.divergent} divergent, \{self.rejected} rejected)"
}

///|
/// Render a table compactly so a reader can see it inside a report line.
///
/// Fields are delimited by `|` and empty fields are rendered as `␀` so that a
/// missing field is visible instead of collapsing into the surrounding
/// whitespace. This is a *display* format, not a parseable one; its only job is
/// to make a divergence legible in a report.
///
/// Written by hand rather than via the `Show`/`Debug` promotions: those are
/// debugging aids whose output format is not part of this library's contract,
/// and a report that the ecosystem reads should not shift under it when a
/// dependency reformats an array.
pub fn render_table(t : Table) -> String {
  let out = StringBuilder()
  out.write_char('[')
  let mut r = 0
  while r < t.length() {
    if r > 0 {
      out.write_char(';')
    }
    out.write_char('[')
    let mut c = 0
    while c < t[r].length() {
      if c > 0 {
        out.write_char('|')
      }
      if t[r][c].length() == 0 {
        out.write_char('\u{2400}')
      } else {
        out.write_string(t[r][c])
      }
      c = c + 1
    }
    out.write_char(']')
    r = r + 1
  }
  out.write_char(']')
  out.to_string()
}

///|
/// One divergence as a single report line, e.g.
///
///     case 12: DIVERGENT doc="a,b\r\n" expected=[[a|b]] actual=[[a]]
///
/// `DOC` is shown with its line breaks escaped so that a multi-line document
/// does not break the report's one-line-per-case shape.
pub fn Divergence::to_line(self : Divergence) -> String {
  let kind = match self.verdict {
    Verdict::Conform => "CONFORM"
    Verdict::Divergent => "DIVERGENT"
    Verdict::Rejected => "REJECTED"
  }
  let tail = match self.verdict {
    Verdict::Rejected => " message=\"" + self.message + "\""
    _ => " actual=" + render_table(self.actual)
  }
  "case \{self.index}: \{kind} doc=\"" +
  escape_line_breaks(self.doc) +
  "\" expected=" +
  render_table(self.expected) +
  tail
}

///|
/// One case rendered as a single trace line, e.g.
///
///     #case 604 doc="a""b,...\r\n" expected=[[a"b|...]]
///
/// Used as the `on_case` callback when a caller wants to survive a candidate's
/// panic with a usable finding: whatever the candidate does, the last line
/// written names the document it was handed.
pub fn describe_case(index : Int, case : CorpusCase) -> String {
  "#case \{index} doc=\"" +
  escape_line_breaks(case.doc) +
  "\" expected=" +
  render_table(case.expected)
}

///|
/// Replace CR and LF with visible escapes so a document fits on one line.
fn escape_line_breaks(s : String) -> String {
  let out = StringBuilder()
  for ch in s {
    if ch == '\r' {
      out.write_string("\\r")
    } else if ch == '\n' {
      out.write_string("\\n")
    } else if ch == '\t' {
      out.write_string("\\t")
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}
