import Foundation

/// Parses a raw terminal output string into segments of plain text and file paths.
struct LineParser {

    // Matches absolute paths (/foo/bar) and home-relative paths (~/foo)
    private static let pathPattern = #"(?:~|(?:/[\w.\-@%+ ]+)+)(?:/[\w.\-@%+ ]*)*"#
    private static let regex = try? NSRegularExpression(pattern: pathPattern)

    static func parse(_ line: String) -> [ParsedSegment] {
        guard let regex else { return [.text(line)] }

        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        let matches = regex.matches(in: line, range: fullRange)

        guard !matches.isEmpty else { return [.text(line)] }

        var segments: [ParsedSegment] = []
        var cursor = 0

        for match in matches {
            let matchRange = match.range

            // Text before this match
            if matchRange.location > cursor {
                let pre = nsLine.substring(with: NSRange(location: cursor, length: matchRange.location - cursor))
                if !pre.isEmpty { segments.append(.text(pre)) }
            }

            let rawPath = nsLine.substring(with: matchRange)
            // Expand ~ to home directory
            let expandedPath = rawPath.hasPrefix("~")
                ? (rawPath as NSString).expandingTildeInPath
                : rawPath

            // Only treat as interactive if the path actually exists on disk
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDir) {
                segments.append(.path(expandedPath, isDirectory: isDir.boolValue))
            } else {
                segments.append(.text(rawPath))
            }

            cursor = matchRange.location + matchRange.length
        }

        // Remaining text after last match
        if cursor < nsLine.length {
            let tail = nsLine.substring(from: cursor)
            if !tail.isEmpty { segments.append(.text(tail)) }
        }

        return segments
    }
}
