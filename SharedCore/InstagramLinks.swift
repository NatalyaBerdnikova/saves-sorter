import Foundation

enum InstagramLinks {
    static func extract(from text: String) -> [InstagramLink] {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?<![A-Za-z0-9])(?:https?://)?(?:www\.)?instagram\.com/(?:[A-Za-z0-9._]+/)?(p|reel|reels|tv)/([A-Za-z0-9_-]+)"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var links: [InstagramLink] = []
        var seen: Set<String> = []
        expression.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  let kindRange = Range(match.range(at: 1), in: text),
                  let codeRange = Range(match.range(at: 2), in: text) else { return }
            let kindText = String(text[kindRange]).lowercased()
            let shortcode = String(text[codeRange])
            guard let kind = mediaKind(kindText), seen.insert(shortcode).inserted else { return }
            links.append(
                InstagramLink(
                    shortcode: shortcode,
                    kind: kind,
                    canonicalURL: canonicalURL(shortcode: shortcode, kind: kind)
                )
            )
        }
        return links
    }

    static func canonicalURL(shortcode: String, kind: MediaKind) -> String {
        "https://www.instagram.com/\(kind.primaryPath)/\(shortcode)/"
    }

    private static func mediaKind(_ raw: String) -> MediaKind? {
        switch raw {
        case "p": return .post
        case "reel": return .reel
        case "reels": return .reels
        case "tv": return .tv
        default: return nil
        }
    }
}
