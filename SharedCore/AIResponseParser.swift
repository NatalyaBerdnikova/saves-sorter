import Foundation

struct AIPlace: Equatable, Decodable {
    var name: String
    var city: String?
    var country: String?
}

struct AIItem: Equatable {
    var what: String
    var shop: String?
    var city: String?
    var country: String?
}

struct AIPayload: Equatable {
    var category: String
    var places: [AIPlace]
    var items: [AIItem]
}

enum AIResponseParser {
    static func parse(text: String) -> AIPayload? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("```") {
            raw = stripFence(raw)
        }
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start <= end else {
            return nil
        }
        let json = String(raw[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        guard let decoded = try? JSONDecoder().decode(PayloadDTO.self, from: data) else { return nil }
        return AIPayload(category: decoded.category ?? "none", places: decoded.places ?? [], items: decoded.items ?? [])
    }

    static func drafts(from payload: AIPayload, lexicon: GeoLexicon, fallbackCities: [City] = []) -> [DraftEntry] {
        let onlyCity = fallbackCities.count == 1 ? fallbackCities[0] : nil
        var entries: [DraftEntry] = []
        for place in payload.places {
            let title = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            var normalized = lexicon.normalize(city: place.city, country: place.country)
            if normalized.city == nil, let onlyCity {
                normalized.city = onlyCity.nameRu
                normalized.country = normalized.country ?? lexicon.country(for: onlyCity)?.nameRu
            }
            let hasCity = normalized.city?.nilIfBlank != nil
            entries.append(
                DraftEntry(
                    kind: .visit,
                    title: title,
                    shop: nil,
                    city: normalized.city,
                    country: normalized.country,
                    needsReview: !hasCity,
                    confidence: hasCity ? 0.8 : 0.45
                )
            )
        }
        for item in payload.items {
            let title = item.what.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            var normalized = lexicon.normalize(city: item.city, country: item.country)
            if normalized.city == nil, let onlyCity {
                normalized.city = onlyCity.nameRu
                normalized.country = normalized.country ?? lexicon.country(for: onlyCity)?.nameRu
            }
            let hasCity = normalized.city?.nilIfBlank != nil
            entries.append(
                DraftEntry(
                    kind: .buy,
                    title: title,
                    shop: item.shop?.nilIfBlank,
                    city: normalized.city,
                    country: normalized.country,
                    needsReview: !hasCity,
                    confidence: hasCity ? 0.8 : 0.45
                )
            )
        }
        return entries
    }

    private static func stripFence(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}

private struct PayloadDTO: Decodable {
    var category: String?
    var places: [AIPlace]?
    var items: [AIItem]?
}

extension AIItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case what
        case shop
        case city
        case country
        case place = "where"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        what = try container.decodeIfPresent(String.self, forKey: .what) ?? ""
        if let shop = try container.decodeIfPresent(String.self, forKey: .place) {
            self.shop = shop
        } else {
            shop = try container.decodeIfPresent(String.self, forKey: .shop)
        }
        city = try container.decodeIfPresent(String.self, forKey: .city)
        country = try container.decodeIfPresent(String.self, forKey: .country)
    }
}
