// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

// Applies `ShatlTypograph` to every `<language>.lproj/Localizable.strings`.
// Run through `Scripts/typograph.sh`; `--check` changes nothing and fails
// when a string is not typeset yet.

import Foundation

let arguments = CommandLine.arguments.dropFirst()
let checkOnly = arguments.contains("--check")
let rootPath = arguments.first { !$0.hasPrefix("--") } ?? FileManager.default.currentDirectoryPath
let root = URL(fileURLWithPath: rootPath, isDirectory: true)

/// One `"key" = "value";` line; comments and blank lines pass through.
let linePattern = try! NSRegularExpression(pattern: #"^(\s*"[^"]+"\s*=\s*")((?:[^"\\]|\\.)*)("\s*;.*)$"#)

func unescape(_ value: String) -> String {
    var result = ""
    var iterator = value.makeIterator()
    while let character = iterator.next() {
        guard character == "\\", let next = iterator.next() else {
            result.append(character)
            continue
        }
        switch next {
        case "n": result.append("\n")
        case "t": result.append("\t")
        default: result.append(next)
        }
    }
    return result
}

func escape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\t", with: "\\t")
}

func visible(_ text: String) -> String {
    text
        .replacingOccurrences(of: ShatlTypograph.noBreakSpace, with: "⍽")
        .replacingOccurrences(of: ShatlTypograph.narrowNoBreakSpace, with: "⌴")
        .replacingOccurrences(of: ShatlTypograph.noBreakHyphen, with: "‑̲")
}

var changedCount = 0

for language in ShatlTypograph.languages {
    let fileURL = root.appendingPathComponent("\(language).lproj/Localizable.strings")
    guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
        FileHandle.standardError.write(Data("Cannot read \(fileURL.path)\n".utf8))
        exit(2)
    }

    var lines = source.components(separatedBy: "\n")
    var changedInFile = 0

    for index in lines.indices {
        let line = lines[index]
        let range = NSRange(line.startIndex..., in: line)
        guard let match = linePattern.firstMatch(in: line, range: range),
              let headRange = Range(match.range(at: 1), in: line),
              let valueRange = Range(match.range(at: 2), in: line),
              let tailRange = Range(match.range(at: 3), in: line)
        else { continue }

        let value = unescape(String(line[valueRange]))
        let typeset = ShatlTypograph.apply(value, language: language)
        guard typeset != value else { continue }

        changedInFile += 1
        print("\(language): \(visible(value))\n    → \(visible(typeset))")
        lines[index] = String(line[headRange]) + escape(typeset) + String(line[tailRange])
    }

    changedCount += changedInFile
    if changedInFile > 0, !checkOnly {
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

if checkOnly {
    print(changedCount == 0 ? "All strings are typeset." : "\(changedCount) strings need typesetting: run Scripts/typograph.sh")
    exit(changedCount == 0 ? 0 : 1)
}
print(changedCount == 0 ? "All strings are typeset." : "Typeset \(changedCount) strings.")
