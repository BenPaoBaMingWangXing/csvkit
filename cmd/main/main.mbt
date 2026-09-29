// csvkit — command line interface.
//
// A small demonstration that the library is usable from a real program, which
// is a separate claim from "the library is correct". It supports the operations
// the library is built around:
//
//   csvkit count <file>     parse and report record/field counts
//   csvkit check <file>     parse, then print structural diagnostics
//   csvkit csv <file>       re-serialize through the library to stdout
//   csvkit version          print the library version
//
// Exit codes: 0 success, 1 a CSV error or reported issue, 2 a usage or I/O
// error. The distinction matters in a pipeline: a malformed file and a mistyped
// command are different failures and should be distinguishable without parsing
// stderr text.

///|
/// Entry point.
fn main {
  // argv[0] is the program name, so the first real argument is argv[1].
  let args = @env.args()
  if args.length() < 2 {
    usage()
    @sys.exit(2)
    return
  }
  let cmd = args[1]
  if cmd == "version" || cmd == "--version" {
    println("csvkit \{@csvkit.version()}")
    return
  }
  if cmd == "help" || cmd == "--help" {
    usage()
    return
  }
  if args.length() < 3 {
    println("csvkit: missing <file> argument for \{cmd}")
    usage()
    @sys.exit(2)
    return
  }
  let path = args[2]
  let text = match read_or_none(path) {
    Some(t) => t
    None => {
      println("csvkit: cannot read \{path}")
      @sys.exit(2)
      return
    }
  }
  match cmd {
    "count" => run_count(text)
    "check" => run_check(text)
    "csv" =>
      match @csvkit.parse(text) {
        Err(e) => fail(e)
        Ok(rows) => println(@csvkit.serialize(rows))
      }
    _ => {
      println("csvkit: unknown command \{cmd}")
      usage()
      @sys.exit(2)
    }
  }
}

///|
/// Read a file, converting an I/O failure into `None`.
///
/// The library's error type deliberately says nothing about I/O, so the
/// conversion happens here, once, at the boundary.
fn read_or_none(path : String) -> String? {
  Some(@fs.read_file_to_string(path)) catch {
    _ => None
  }
}

///|
/// Report how many records and fields a document contains.
fn run_count(text : String) -> Unit {
  match @csvkit.parse(text) {
    Err(e) => fail(e)
    Ok(rows) => {
      let mut fields = 0
      let mut i = 0
      while i < rows.length() {
        fields = fields + rows[i].length()
        i = i + 1
      }
      println("records: \{rows.length()}")
      println("fields:  \{fields}")
      let report = @csvkit.diagnose(rows)
      println("columns: \{report.columns}")
      if !report.is_clean() {
        println("issues:  \{report.issues.length()}")
      }
    }
  }
}

///|
/// Parse a document, then print each structural issue it contains.
fn run_check(text : String) -> Unit {
  match @csvkit.parse(text) {
    Err(e) => fail(e)
    Ok(rows) => {
      let report = @csvkit.diagnose(rows)
      if report.is_clean() {
        println(
          "ok: \{report.records} records, \{report.columns} columns, no issues",
        )
      } else {
        for line in report.to_lines() {
          println(line)
        }
        @sys.exit(1)
      }
    }
  }
}

///|
/// Print a CSV error and exit non-zero.
fn fail(e : @csvkit.CsvError) -> Unit {
  println("csvkit: \{e.to_message()}")
  @sys.exit(1)
}

///|
/// Print the command synopsis.
fn usage() -> Unit {
  println("usage: csvkit <command> <file>")
  println("")
  println("  count <file>   number of records, fields and columns")
  println("  check <file>   structural diagnostics (ragged rows, bad headers)")
  println("  csv <file>     re-serialize through the library to stdout")
  println("  version        print the library version")
}
