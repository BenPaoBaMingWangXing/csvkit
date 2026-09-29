// csvkit — an RFC 4180 CSV parsing and serialisation engine for MoonBit.
//
// A note on `preferred_target`: `wasm` is listed because it is the backend the
// test suite is run against in CI and the one the library is developed on. It
// is a preference, not a restriction — the library is pure MoonBit with no FFI,
// and CI builds it for wasm, wasm-gc, js and native alike.

name = "BenPaoBaMingWangXing/csvkit"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/BenPaoBaMingWangXing/csvkit"

license = "Apache-2.0"

keywords = [ "csv", "rfc4180", "parser", "serializer", "text" ]

preferred_target = "wasm"

description = "RFC 4180 CSV parsing, serialisation and structural diagnostics, with differential conformance evidence against an independent implementation."

import {
  "moonbitlang/x@0.5.5",
}
