import Foundation

enum ExportService {
    static let csvHeader = "Name,Address,City,Country,Note,Instagram link"

    static func csv(entries: [LibraryEntry], note: (LibraryEntry) -> String = { $0.note ?? "" }) -> String {
        var lines = [csvHeader]
        for entry in entries {
            let placeName = mapName(for: entry)
            let address = [placeName, entry.city, entry.country]
                .compactMap { $0?.nilIfBlank }
                .joined(separator: ", ")
            var noteText = note(entry)
            if entry.kind == .buy,
               let shop = entry.shop?.nilIfBlank,
               shop.caseInsensitiveCompare(entry.title) != .orderedSame {
                let prefix = "Что купить: \(entry.title)"
                noteText = noteText.isEmpty ? prefix : prefix + ". " + noteText
            }
            let fields = [placeName, address, entry.city ?? "", entry.country ?? "", noteText, entry.instagramURL]
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\n") + "\n"
    }

    static func namesList(entries: [LibraryEntry]) -> String {
        entries.map { entry in
            if entry.kind == .buy, let shop = entry.shop?.nilIfBlank, shop.caseInsensitiveCompare(entry.title) != .orderedSame {
                return "\(entry.title) — \(shop)"
            }
            return entry.title
        }.joined(separator: "\n")
    }

    static func mapName(for entry: LibraryEntry) -> String {
        if entry.kind == .buy, let shop = entry.shop?.nilIfBlank {
            return shop
        }
        return entry.title
    }

    static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

enum MapsLink {
    static func url(for entry: LibraryEntry) -> URL? {
        let parts = [ExportService.mapName(for: entry), entry.city, entry.country].compactMap { $0?.nilIfBlank }
        return url(queryParts: parts)
    }

    static func url(queryParts: [String]) -> URL? {
        let query = queryParts.filter { !$0.isEmpty }.joined(separator: ", ")
        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: query),
        ]
        return components?.url
    }
}

enum LibraryGrouping {
    struct CityGroup: Equatable {
        var city: String
        var visits: [LibraryEntry]
        var buys: [LibraryEntry]
    }

    struct CountryGroup: Equatable {
        var country: String
        var cities: [CityGroup]
    }

    static func confirmed(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        entries.filter { !$0.needsReview && !($0.city ?? "").isEmpty && !($0.country ?? "").isEmpty }
    }

    static func withoutCity(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        entries.filter { $0.needsReview && ($0.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func countries(from entries: [LibraryEntry]) -> [CountryGroup] {
        let rows = confirmed(entries)
        var countryOrder: [String] = []
        var byCountry: [String: [String: [LibraryEntry]]] = [:]
        for entry in rows {
            let country = entry.country ?? ""
            let city = entry.city ?? ""
            if byCountry[country] == nil {
                countryOrder.append(country)
                byCountry[country] = [:]
            }
            byCountry[country, default: [:]][city, default: []].append(entry)
        }
        let groups = countryOrder.map { country -> CountryGroup in
            let cities = byCountry[country] ?? [:]
            let cityGroups = cities.keys.sorted(by: ruSort).map { city in
                let items = cities[city] ?? []
                return CityGroup(
                    city: city,
                    visits: items.filter { $0.kind == .visit },
                    buys: items.filter { $0.kind == .buy }
                )
            }
            return CountryGroup(country: country, cities: cityGroups)
        }
        return groups.sorted { ruSort($0.country, $1.country) }
    }

    private static func ruSort(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, locale: Locale(identifier: "ru_RU")) == .orderedAscending
    }
}

enum LibraryMerge {
    static func merge(base: Library, incoming: Library) -> Library {
        var result = base
        var postMap: [UUID: UUID] = [:]
        for post in incoming.posts {
            if let existing = result.posts.first(where: { $0.shortcode == post.shortcode }) {
                postMap[post.id] = existing.id
            } else {
                result.posts.append(post)
                postMap[post.id] = post.id
            }
        }
        for entry in incoming.entries {
            guard let mappedPost = postMap[entry.postId] else { continue }
            var copy = entry
            copy.postId = mappedPost
            let duplicate = result.entries.contains { existing in
                existing.id == copy.id || (
                    existing.postId == copy.postId &&
                    existing.kind == copy.kind &&
                    existing.title == copy.title &&
                    existing.city == copy.city &&
                    existing.shop == copy.shop
                )
            }
            if !duplicate {
                result.entries.append(copy)
            }
        }
        return result
    }
}
