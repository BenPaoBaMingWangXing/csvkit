// csvkit — ecosystem conformance, one candidate per process.
//
// Runs `testdata/differential.tsv` — the 1078 documents produced by Python
// 3.13's `csv` module — through one MoonBit implementation of the same grammar
// and prints what it does. The corpus and the comparison rules come from the
// library (`conformance.mbt`), so this tool measures with exactly the machinery
// the library's own differential test uses.
//
// Why one candidate per process
// -----------------------------
// A candidate is somebody else's code, and a candidate can *panic*. That is not
// hypothetical: `maria/csv_parser` aborts on a document containing a character
// outside the Basic Multilingual Plane, and that abort cannot be caught —
// MoonBit panics are not `raise`s, so `try`/`catch` does not see them, and the
// process dies with whatever it had already printed.
//
// If all candidates ran in one process, one abort would take the whole report
// with it and the report would say nothing about anybody. So the unit of
// execution is a single candidate selected on the command line, and the driver
// (`tools/conformance_report.py`) starts a fresh process per candidate. A
// candidate that dies loses its own line and is recorded as ABORTED; the rest
// of the report is unaffected.
//
// Usage:
//   moon run conformance -- --list     list candidate slugs
//   moon run conformance -- <slug>     run one candidate
//
// Exit codes: 0 the candidate ran, 1 the corpus could not be read, 2 a usage
// error (unknown slug, or no argument).

///|
/// Where the corpus lives, relative to the module root (which is the working
/// directory `moon run` uses).
const CORPUS_PATH : String = "testdata/differential.tsv"

///|
/// Entry point.
fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    @sys.exit(2)
    return
  }
  let selector = args[1]
  if selector == "--list" {
    // Slug and label are printed together so a driver can name a candidate
    // whose run never reached the point of printing its own summary line —
    // which is exactly what happens when a candidate panics.
    for entry in candidates() {
      println(entry.0 + "\t" + entry.1)
    }
    return
  }
  if selector == "--help" || selector == "help" {
    usage()
    return
  }
  let text = match read_or_none(CORPUS_PATH) {
    Some(t) => t
    None => {
      println("conformance: cannot read \{CORPUS_PATH}")
      @sys.exit(1)
      return
    }
  }
  let cases = load_corpus(text)
  if cases.length() == 0 {
    println("conformance: \{CORPUS_PATH} contained no usable cases")
    @sys.exit(1)
    return
  }
  // `--trace` prints each case immediately before the candidate is handed it.
  // A candidate that panics leaves that line behind as the only evidence of
  // *which* document killed it, which is the difference between "this library
  // crashed" and "this library crashes on this input".
  let tracing = has_flag(args, "--trace")
  let on_case = if tracing {
    Some(fn(index : Int) { println(@csvkit.describe_case(index, cases[index])) })
  } else {
    None
  }
  match run_candidate(selector, cases, on_case) {
    Some(summary) => {
      println(summary.to_line())
      print_samples(
        summary,
        summary.divergent_samples,
        "DIVERGENT",
        summary.divergent,
      )
      print_samples(
        summary,
        summary.rejected_samples,
        "REJECTED",
        summary.rejected,
      )
    }
    None => {
      println("conformance: unknown candidate '\{selector}' (try --list)")
      @sys.exit(2)
    }
  }
}

///|
/// True when `flag` appears anywhere in the argument list.
fn has_flag(args : Array[String], flag : String) -> Bool {
  let mut found = false
  let mut i = 0
  while i < args.length() {
    if args[i] == flag {
      found = true
    }
    i = i + 1
  }
  found
}

///|
/// Dispatch a slug to its candidate.
///
/// `None` means the slug is not one of ours, which is a usage error rather than
/// a conformance result — a typo must not look like a clean run.
fn run_candidate(
  slug : String,
  cases : Array[@csvkit.CorpusCase],
  on_case : ((Int) -> Unit)?,
) -> @csvkit.Summary? {
  match slug {
    "csvkit" => Some(@csvkit.run_corpus(Csvkit, cases, on_case))
    "maria" => Some(@csvkit.run_corpus(Maria, cases, on_case))
    "mbitsv-default" => Some(@csvkit.run_corpus(Mbitsv, cases, on_case))
    "mbitsv-strict-off" =>
      Some(@csvkit.run_corpus(MbitsvLenientColumns, cases, on_case))
    _ => None
  }
}

///|
/// The candidate registry: slug, display label, and report order.
///
/// Order is fixed so two reports diff cleanly.
fn candidates() -> Array[(String, String)] {
  [
    ("csvkit", "BenPaoBaMingWangXing/csvkit"),
    ("maria", "maria/csv_parser"),
    ("mbitsv-default", "CJR-zhang/mbitsv (default config)"),
    ("mbitsv-strict-off", "CJR-zhang/mbitsv (strict_columns off)"),
  ]
}

///|
/// Print one verdict kind's samples under a heading, or nothing if empty.
///
/// Divergent and rejected are kept apart because they call for different fixes:
/// one candidate returns the wrong records, the other refuses documents the
/// reference accepts. Merging them into a single list of "failures" would hide
/// which of the two is happening.
fn print_samples(
  summary : @csvkit.Summary,
  samples : Array[@csvkit.Divergence],
  heading : String,
  total : Int,
) -> Unit {
  let _ = summary
  if samples.length() == 0 {
    return
  }
  println("  \{heading} \{samples.length()} shown of \{total}")
  for sample in samples {
    println("  " + sample.to_line())
  }
}

///|
/// Read the corpus and decode every line.
///
/// Lines that fail to decode are skipped; `main` treats an empty result as a
/// hard error, so a corpus that lost its content cannot masquerade as a clean
/// report.
fn load_corpus(text : String) -> Array[@csvkit.CorpusCase] {
  let out : Array[@csvkit.CorpusCase] = []
  let lines : Array[StringView] = text.split("\n").collect()
  let mut i = 0
  while i < lines.length() {
    match @csvkit.decode_corpus_line(lines[i].to_owned()) {
      Ok(case) => out.push(case)
      Err(_) => ()
    }
    i = i + 1
  }
  out
}

///|
/// Read a file, converting an I/O failure into `None`.
fn read_or_none(path : String) -> String? {
  Some(@fs.read_file_to_string(path)) catch {
    _ => None
  }
}

///|
/// Print the command synopsis.
fn usage() -> Unit {
  println("usage: moon run conformance -- <slug> [--trace]")
  println("")
  println("  --list    list candidate slugs")
  println("  --trace   print each case before handing it to the candidate, so")
  println("            a candidate that panics leaves the culprit behind")
  println("")
  println("Runs the RFC 4180 differential corpus through one candidate and")
  println("reports where it disagrees with the reference. One candidate per")
  println("process, so a candidate that panics does not take the rest of the")
  println("report with it.")
}
