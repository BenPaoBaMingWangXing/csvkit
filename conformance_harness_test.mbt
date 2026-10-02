// csvkit — tests for the conformance layer itself.
//
// The framework in `conformance.mbt` is what the library offers to *other*
// implementations, so it is held to the same standard as the parser: it is
// tested, and its most easily-misread behaviour is pinned by an explicit test.
// A verifier that quietly reports the wrong thing is worse than no verifier.
//
// The behaviour worth pinning hardest is the Divergent/Rejected split. It is
// tempting to treat "refused the document" as the safe, conservative outcome.
// For a *conformance* report it is the opposite: every document in the corpus
// was produced by an independent implementation and read back by it, so a
// document in the corpus is legal by construction. Refusing one means dropping
// data that the reference recovers, which is a divergence, not caution.

///|
/// Decode the corpus encoding: `base64(document) TAB base64(json(records))`.
test "conformance: decode_corpus_line decodes the corpus encoding" {
  // "YQ0K" is base64 of "a\r\n"; "W1siYSJdXQ==" is base64 of [["a"]].
  let ok = match @csvkit.decode_corpus_line("YQ0K\tW1siYSJdXQ==") {
    Ok(c) =>
      c.doc == "a\r\n" && c.expected.length() == 1 && c.expected[0][0] == "a"
    Err(_) => false
  }
  inspect(ok, content="true")
}

///|
/// A corpus that has been truncated, hand-edited, or had its line endings
/// mangled must fail loudly rather than silently contributing zero cases.
test "conformance: decode_corpus_line rejects malformed lines" {
  let blanks = match @csvkit.decode_corpus_line("") {
    Err(_) => true
    Ok(_) => false
  }
  let no_tab = match @csvkit.decode_corpus_line("no separator here") {
    Err(_) => true
    Ok(_) => false
  }
  let empty_right = match @csvkit.decode_corpus_line("YQ0K\t") {
    Err(_) => true
    Ok(_) => false
  }
  let bad_base64 = match @csvkit.decode_corpus_line("!!!!\t!!!!") {
    Err(_) => true
    Ok(_) => false
  }
  inspect(blanks && no_tab && empty_right && bad_base64, content="true")
}

///|
/// Ragged records must not be normalised before comparison.
///
/// RFC 4180 permits records with differing field counts, so `["c"]` and
/// `["c", ""]` are genuinely different results. Padding or truncating them to
/// match would hide the disagreement the corpus exists to surface.
test "conformance: tables_equal does not normalise ragged records" {
  let ragged_vs_wider = @csvkit.tables_equal([["a", "b"], ["c"]], [
    ["a", "b"],
    ["c", "d"],
  ])
  let ragged_vs_padded = @csvkit.tables_equal([["a", "b"], ["c"]], [
    ["a", "b"],
    ["c", ""],
  ])
  let identical = @csvkit.tables_equal([["a", "b"], ["c"]], [["a", "b"], ["c"]])
  inspect(!ragged_vs_wider && !ragged_vs_padded && identical, content="true")
}

///|
/// A candidate that refuses a legal document is reported as `Rejected`, and one
/// that returns different records is reported as `Divergent`. The two are
/// counted separately because they need different fixes: one is a parser that
/// is too strict, the other a parser that is wrong.
test "conformance: the framework separates divergence from rejection" {
  let cases : Array[@csvkit.CorpusCase] = [
    { doc: "a\r\n", expected: [["a"]], },
    { doc: "b\r\n", expected: [["b"]], },
  ]
  let faithful = @csvkit.run_corpus(Faithful, cases, None)
  let sloppy = @csvkit.run_corpus(Sloppy, cases, None)
  let rejecting = @csvkit.run_corpus(Rejecting, cases, None)
  inspect(faithful.failures(), content="0")
  // Sloppy parses both documents but always returns no records.
  inspect(sloppy.divergent, content="2")
  inspect(sloppy.rejected, content="0")
  // Rejecting refuses both documents; that is a divergence, not caution.
  inspect(rejecting.rejected, content="2")
  inspect(rejecting.divergent, content="0")
  // A refusal carries the implementation's own explanation into the report.
  inspect(rejecting.rejected_samples[0].message, content="refused")
  // Samples are kept per verdict kind, so a candidate that fails in only one
  // mode does not crowd the other mode out of the report.
  inspect(rejecting.divergent_samples.length(), content="0")
  inspect(sloppy.rejected_samples.length(), content="0")
}

///|
/// A candidate for the conformance tests: one that is right, one that parses
/// but disagrees, one that refuses everything.
enum Faithful {
  Faithful
}

///|
enum Sloppy {
  Sloppy
}

///|
enum Rejecting {
  Rejecting
}

///|
impl @csvkit.CsvCandidate for Faithful with fn label(_self) {
  "faithful"
}

///|
impl @csvkit.CsvCandidate for Faithful with fn parse(_self, input) {
  match input {
    "a\r\n" => Ok([["a"]])
    "b\r\n" => Ok([["b"]])
    _ => Ok([])
  }
}

///|
impl @csvkit.CsvCandidate for Sloppy with fn label(_self) {
  "sloppy"
}

///|
impl @csvkit.CsvCandidate for Sloppy with fn parse(_self, _input) {
  Ok([])
}

///|
impl @csvkit.CsvCandidate for Rejecting with fn label(_self) {
  "rejecting"
}

///|
impl @csvkit.CsvCandidate for Rejecting with fn parse(_self, _input) {
  Err("refused")
}
