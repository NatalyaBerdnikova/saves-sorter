import Foundation

enum HTMLEntities {
    private static let named: [String: String] = [
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "nbsp": "\u{00A0}",
        "laquo": "«",
        "raquo": "»",
        "mdash": "—",
        "ndash": "–",
        "hellip": "…",
        "rsquo": "’",
        "lsquo": "‘",
        "ldquo": "“",
        "rdquo": "”",
        "bull": "•",
        "middot": "·",
    ]

    static func decode(_ string: String) -> String {
        var current = string
        for _ in 0..<2 {
            let next = decodeOnce(current)
            if next == current { break }
            current = next
        }
        return current
    }

    private static func decodeOnce(_ string: String) -> String {
        var result = ""
        var index = string.startIndex
        while index < string.endIndex {
            if string[index] == "&" {
                let rest = string[index...]
                if let semi = rest.firstIndex(of: ";"), string.distance(from: index, to: semi) <= 12 {
                    let body = string[string.index(after: index)..<semi]
                    if let replacement = replacement(for: String(body)) {
                        result.append(replacement)
                        index = string.index(after: semi)
                        continue
                    }
                }
            }
            result.append(string[index])
            index = string.index(after: index)
        }
        return result
    }

    private static func replacement(for body: String) -> String? {
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                let hex = String(digits.dropFirst())
                guard let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) else { return nil }
                return String(Character(scalar))
            }
            guard let value = UInt32(digits), let scalar = UnicodeScalar(value) else { return nil }
            return String(Character(scalar))
        }
        return named[body.lowercased()]
    }
}

struct MetaTag {
    var attributes: [String: String]

    var name: String? { attributes["name"] }
    var property: String? { attributes["property"] }
    var content: String? { attributes["content"] }
}

enum MetaScanner {
    static func tags(in html: String) -> [MetaTag] {
        var result: [MetaTag] = []
        var searchStart = html.startIndex
        while searchStart < html.endIndex,
              let found = html.range(of: "<meta", options: .caseInsensitive, range: searchStart..<html.endIndex) {
            guard let close = endOfTag(html, from: found.lowerBound) else { break }
            let innerStart = found.upperBound
            let inner = innerStart < close ? String(html[innerStart..<close]) : ""
            result.append(MetaTag(attributes: parseAttributes(inner)))
            searchStart = html.index(after: close)
        }
        return result
    }

    private static func endOfTag(_ html: String, from start: String.Index) -> String.Index? {
        var index = start
        var quote: Character?
        while index < html.endIndex {
            let character = html[index]
            if let active = quote {
                if character == active { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return index
            }
            index = html.index(after: index)
        }
        return nil
    }

    private static func parseAttributes(_ source: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var index = source.startIndex
        while index < source.endIndex {
            while index < source.endIndex, source[index].isWhitespace || source[index] == "/" {
                index = source.index(after: index)
            }
            if index >= source.endIndex { break }
            let nameStart = index
            while index < source.endIndex, isName(source[index]) {
                index = source.index(after: index)
            }
            let name = String(source[nameStart..<index]).lowercased()
            guard !name.isEmpty else {
                index = source.index(after: index)
                continue
            }
            while index < source.endIndex, source[index].isWhitespace {
                index = source.index(after: index)
            }
            guard index < source.endIndex, source[index] == "=" else { continue }
            index = source.index(after: index)
            while index < source.endIndex, source[index].isWhitespace {
                index = source.index(after: index)
            }
            guard index < source.endIndex else { break }
            let value: String
            let opener = source[index]
            if opener == "\"" || opener == "'" {
                index = source.index(after: index)
                let valueStart = index
                while index < source.endIndex, source[index] != opener {
                    index = source.index(after: index)
                }
                value = String(source[valueStart..<index])
                if index < source.endIndex { index = source.index(after: index) }
            } else {
                let valueStart = index
                while index < source.endIndex, !source[index].isWhitespace, source[index] != ">" {
                    index = source.index(after: index)
                }
                value = String(source[valueStart..<index])
            }
            attributes[name] = HTMLEntities.decode(value)
        }
        return attributes
    }

    private static func isName(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == ":"
    }
}

enum HTMLSlice {
    static func innerHTML(ofDivWithClassToken token: String, in html: String) -> String? {
        var search = html.startIndex
        while search < html.endIndex,
              let found = html.range(of: "<div", options: .caseInsensitive, range: search..<html.endIndex) {
            guard let tagEnd = endOfTag(html, from: found.lowerBound) else { return nil }
            let opening = String(html[found.lowerBound...tagEnd])
            if classTokens(in: opening).contains(token) {
                let contentStart = html.index(after: tagEnd)
                if let contentEnd = balancedClose(html, from: contentStart) {
                    return String(html[contentStart..<contentEnd])
                }
                return nil
            }
            search = html.index(after: tagEnd)
        }
        return nil
    }

    static func removingDiv(classToken: String, in html: String) -> String {
        guard let innerStartRange = rangeOfDiv(classToken: classToken, in: html) else { return html }
        var copy = html
        copy.removeSubrange(innerStartRange)
        return copy
    }

    static func strip(_ html: String) -> String {
        var result = ""
        var index = html.startIndex
        while index < html.endIndex {
            if html[index] == "<" {
                if starts(html, at: index, with: "<br") {
                    result.append("\n")
                }
                if let end = endOfTag(html, from: index) {
                    index = html.index(after: end)
                    continue
                }
            }
            result.append(html[index])
            index = html.index(after: index)
        }
        let decoded = HTMLEntities.decode(result)
        let lines = decoded.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let trimmed = lines.map { line in
            line.replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        return trimmed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rangeOfDiv(classToken: String, in html: String) -> Range<String.Index>? {
        var search = html.startIndex
        while search < html.endIndex,
              let found = html.range(of: "<div", options: .caseInsensitive, range: search..<html.endIndex) {
            guard let tagEnd = endOfTag(html, from: found.lowerBound) else { return nil }
            let opening = String(html[found.lowerBound...tagEnd])
            if classTokens(in: opening).contains(classToken) {
                let contentStart = html.index(after: tagEnd)
                guard let contentEnd = balancedClose(html, from: contentStart) else { return nil }
                guard let closeEnd = endOfTag(html, from: contentEnd) else { return nil }
                return found.lowerBound..<html.index(after: closeEnd)
            }
            search = html.index(after: tagEnd)
        }
        return nil
    }

    private static func classTokens(in openingTag: String) -> [String] {
        guard let classRange = openingTag.range(of: "class", options: .caseInsensitive) else { return [] }
        var index = classRange.upperBound
        while index < openingTag.endIndex, openingTag[index].isWhitespace { index = openingTag.index(after: index) }
        guard index < openingTag.endIndex, openingTag[index] == "=" else { return [] }
        index = openingTag.index(after: index)
        while index < openingTag.endIndex, openingTag[index].isWhitespace { index = openingTag.index(after: index) }
        guard index < openingTag.endIndex else { return [] }
        let quote = openingTag[index]
        guard quote == "\"" || quote == "'" else { return [] }
        index = openingTag.index(after: index)
        let start = index
        while index < openingTag.endIndex, openingTag[index] != quote { index = openingTag.index(after: index) }
        let value = openingTag[start..<index]
        return value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func balancedClose(_ html: String, from contentStart: String.Index) -> String.Index? {
        var depth = 1
        var index = contentStart
        while index < html.endIndex {
            if starts(html, at: index, with: "<div") {
                guard let tagEnd = endOfTag(html, from: index) else { return nil }
                depth += 1
                index = html.index(after: tagEnd)
                continue
            }
            if starts(html, at: index, with: "</div") {
                depth -= 1
                if depth == 0 { return index }
                guard let tagEnd = endOfTag(html, from: index) else { return nil }
                index = html.index(after: tagEnd)
                continue
            }
            index = html.index(after: index)
        }
        return nil
    }

    private static func endOfTag(_ html: String, from start: String.Index) -> String.Index? {
        var index = start
        var quote: Character?
        while index < html.endIndex {
            let character = html[index]
            if let active = quote {
                if character == active { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return index
            }
            index = html.index(after: index)
        }
        return nil
    }

    private static func starts(_ html: String, at index: String.Index, with prefix: String) -> Bool {
        var cursor = index
        for character in prefix {
            if cursor >= html.endIndex { return false }
            if String(html[cursor]).lowercased() != String(character).lowercased() { return false }
            cursor = html.index(after: cursor)
        }
        return true
    }
}

extension String {
    var cleanedCaption: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
