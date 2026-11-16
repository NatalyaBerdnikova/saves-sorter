import Foundation

enum CaptionSource: String, Equatable {
    case metaDescription
    case ogTitle
    case embed
    case mediaJSON
}

struct ParsedPage: Equatable {
    var caption: String?
    var author: String?
    var imageURL: String?
    var isUnavailable: Bool
    var captionSource: CaptionSource?
}

enum CaptionParser {
    static let unavailablePhrases = [
        "The link to this photo or video may be broken",
        "Sorry, this page isn't available",
    ]

    static func parse(pageHTML: String?, embedHTML: String?) -> ParsedPage {
        if let pageHTML, isUnavailable(pageHTML) {
            return ParsedPage(
                caption: nil,
                author: nil,
                imageURL: openGraphImage(in: pageHTML),
                isUnavailable: true,
                captionSource: nil
            )
        }

        var candidates: [Candidate] = []
        var author: String?
        var imageURL: String?

        if let pageHTML {
            let tags = MetaScanner.tags(in: pageHTML)
            imageURL = tags.first { $0.property?.lowercased() == "og:image" }?.content
            if let description = metaContent(tags, names: ["description"], properties: ["og:description"]),
               let extracted = CaptionText.extract(fromMeta: description) {
                candidates.append(Candidate(source: .metaDescription, caption: extracted.caption, author: extracted.author))
                author = extracted.author
            }
            if let title = metaContent(tags, names: [], properties: ["og:title"]),
               let extracted = CaptionText.extract(fromMeta: title) {
                candidates.append(Candidate(source: .ogTitle, caption: extracted.caption, author: extracted.author))
                if author == nil { author = extracted.author }
            }
            if let jsonCaption = JSONCaption.extract(from: pageHTML) {
                candidates.append(Candidate(source: .mediaJSON, caption: jsonCaption, author: nil))
            }
        }

        if let embedHTML, !isUnavailable(embedHTML), let caption = EmbedCaption.extract(from: embedHTML) {
            candidates.append(Candidate(source: .embed, caption: caption, author: nil))
        }

        let usable = candidates
            .map { Candidate(source: $0.source, caption: $0.caption.cleanedCaption, author: $0.author) }
            .filter { !$0.caption.isEmpty }

        guard let best = usable.max(by: prefers) else {
            return ParsedPage(caption: nil, author: author, imageURL: imageURL, isUnavailable: false, captionSource: nil)
        }
        return ParsedPage(
            caption: best.caption,
            author: best.author ?? author,
            imageURL: imageURL,
            isUnavailable: false,
            captionSource: best.source
        )
    }

    static func isUnavailable(_ html: String) -> Bool {
        unavailablePhrases.contains { html.range(of: $0, options: .caseInsensitive) != nil }
    }

    private static func prefers(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.caption.count != rhs.caption.count {
            return lhs.caption.count < rhs.caption.count
        }
        return priority(lhs.source) > priority(rhs.source)
    }

    private static func priority(_ source: CaptionSource) -> Int {
        switch source {
        case .metaDescription: return 0
        case .ogTitle: return 1
        case .mediaJSON: return 2
        case .embed: return 3
        }
    }

    private static func metaContent(_ tags: [MetaTag], names: [String], properties: [String]) -> String? {
        let nameSet = Set(names.map { $0.lowercased() })
        let propertySet = Set(properties.map { $0.lowercased() })
        return tags.first { tag in
            if let name = tag.name?.lowercased(), nameSet.contains(name) { return true }
            if let property = tag.property?.lowercased(), propertySet.contains(property) { return true }
            return false
        }?.content
    }

    private static func openGraphImage(in html: String) -> String? {
        MetaScanner.tags(in: html).first { $0.property?.lowercased() == "og:image" }?.content
    }

    private struct Candidate {
        var source: CaptionSource
        var caption: String
        var author: String?
    }
}

enum CaptionText {
    static func extract(fromMeta text: String) -> (caption: String, author: String?)? {
        let value = text.cleanedCaption
        if value.isEmpty { return nil }
        if let groups = Regex.firstGroups(
            pattern: #"^.+?\s+likes?,\s+.+?\s+comments?\s+-\s+(.+?)\s+on\s+.+?:\s*"(.*)"\s*\.?\s*$"#,
            in: value
        ), groups.count == 2 {
            return (groups[1], groups[0].nilIfBlank)
        }
        if let groups = Regex.firstGroups(
            pattern: #"^(.+?)\s+on Instagram:\s*"(.*)"\s*\.?\s*$"#,
            in: value
        ), groups.count == 2 {
            return (groups[1], groups[0].nilIfBlank)
        }
        if let groups = Regex.firstGroups(
            pattern: #"^(.+?)\s+в Instagram:\s*[«"](.*)[»"]\s*$"#,
            in: value
        ), groups.count == 2 {
            return (groups[1], groups[0].nilIfBlank)
        }
        let lowered = value.lowercased()
        if lowered.contains("нравится") || lowered.contains("коммент"),
           let quoted = lastGuillemet(in: value) {
            return (quoted, nil)
        }
        return nil
    }

    private static func lastGuillemet(in text: String) -> String? {
        guard let open = text.lastIndex(of: "«"),
              let close = text.lastIndex(of: "»"),
              open < close else { return nil }
        let inner = text[text.index(after: open)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
        return inner.isEmpty ? nil : inner
    }
}

enum JSONCaption {
    static func extract(from html: String) -> String? {
        guard let marker = html.range(of: "edge_media_to_caption") else { return nil }
        let windowEnd = html.index(marker.lowerBound, offsetBy: 800, limitedBy: html.endIndex) ?? html.endIndex
        let window = html[marker.lowerBound..<windowEnd]
        guard let key = window.range(of: "\"text\"") else { return nil }
        var index = key.upperBound
        while index < html.endIndex, html[index].isWhitespace {
            index = html.index(after: index)
        }
        guard index < html.endIndex, html[index] == ":" else { return nil }
        index = html.index(after: index)
        while index < html.endIndex, html[index].isWhitespace {
            index = html.index(after: index)
        }
        guard index < html.endIndex, html[index] == "\"" else { return nil }
        index = html.index(after: index)
        return readJSONString(html, from: &index)?.cleanedCaption.nilIfBlank
    }

    private static func readJSONString(_ text: String, from index: inout String.Index) -> String? {
        var result = ""
        while index < text.endIndex {
            let character = text[index]
            if character == "\\" {
                let next = text.index(after: index)
                guard next < text.endIndex else { return nil }
                let escaped = text[next]
                switch escaped {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                case "u":
                    let hexStart = text.index(after: next)
                    guard let hexEnd = text.index(hexStart, offsetBy: 4, limitedBy: text.endIndex),
                          let value = UInt32(text[hexStart..<hexEnd], radix: 16),
                          let scalar = UnicodeScalar(value) else { return nil }
                    result.append(Character(scalar))
                    index = hexEnd
                    continue
                default:
                    result.append(escaped)
                }
                index = text.index(after: next)
                continue
            }
            if character == "\"" { return result }
            result.append(character)
            index = text.index(after: index)
        }
        return nil
    }
}

enum EmbedCaption {
    static func extract(from html: String) -> String? {
        guard var inner = HTMLSlice.innerHTML(ofDivWithClassToken: "Caption", in: html) else { return nil }
        inner = HTMLSlice.removingDiv(classToken: "CaptionUsername", in: inner)
        let text = HTMLSlice.strip(inner).cleanedCaption
        return text.isEmpty ? nil : text
    }
}

enum Regex {
    static func firstGroups(pattern: String, in text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: full) else { return nil }
        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
            groups.append(String(text[swiftRange]))
        }
        return groups
    }
}
