import Foundation

struct Country: Equatable {
    var id: String
    var nameRu: String
    var nameEn: String
}

struct City: Equatable {
    var id: String
    var countryId: String
    var nameRu: String
    var nameEn: String
}

struct GeoMatch: Equatable {
    var range: Range<String.Index>
    var city: City?
    var country: Country?
}

enum GeoLexiconError: Error, Equatable {
    case missingResource
    case invalidData
}

struct GeoLexicon {
    let countries: [Country]
    let cities: [City]
    private let terms: [SearchTerm]
    private let countryByID: [String: Country]

    init(countries: [CountryRecord], cities: [CityRecord]) {
        self.countries = countries.map { Country(id: $0.id, nameRu: $0.ru, nameEn: $0.en) }
        self.cities = cities.map { City(id: $0.id, countryId: $0.country, nameRu: $0.ru, nameEn: $0.en) }
        self.countryByID = Dictionary(uniqueKeysWithValues: self.countries.map { ($0.id, $0) })
        self.terms = Self.makeTerms(countryRecords: countries, cityRecords: cities, countries: self.countries, cities: self.cities)
    }

    init(data: Data) throws {
        let file = try JSONDecoder().decode(GeoFile.self, from: data)
        self.init(countries: file.countries, cities: file.cities)
    }

    static func loadBundled() throws -> GeoLexicon {
        if let url = bundledURL() {
            return try GeoLexicon(data: Data(contentsOf: url))
        }
        throw GeoLexiconError.missingResource
    }

    func country(for city: City) -> Country? {
        countryByID[city.countryId]
    }

    func matches(in text: String) -> [GeoMatch] {
        var occupied: [Range<String.Index>] = []
        var found: [GeoMatch] = []
        for term in terms {
            for range in Self.ranges(of: term.text, in: text, caseSensitive: term.caseSensitive) {
                if occupied.contains(where: { $0.overlaps(range) }) { continue }
                occupied.append(range)
                if let city = term.city {
                    found.append(GeoMatch(range: range, city: city, country: countryByID[city.countryId]))
                } else if let country = term.country {
                    found.append(GeoMatch(range: range, city: nil, country: country))
                }
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    func resolveCity(_ raw: String) -> City? {
        uniqueCities(in: raw).count == 1 ? uniqueCities(in: raw).first : nil
    }

    func resolveCountry(_ raw: String) -> Country? {
        let hits = matches(in: raw).compactMap(\.country)
        var unique: [Country] = []
        for country in hits where !unique.contains(where: { $0.id == country.id }) {
            unique.append(country)
        }
        return unique.count == 1 ? unique[0] : nil
    }

    func uniqueCities(in text: String) -> [City] {
        var unique: [City] = []
        for city in matches(in: text).compactMap(\.city) where !unique.contains(where: { $0.id == city.id }) {
            unique.append(city)
        }
        return unique
    }

    func normalize(city rawCity: String?, country rawCountry: String?) -> (city: String?, country: String?) {
        let resolvedCity = rawCity.flatMap(resolveCity)
        var resolvedCountry = rawCountry.flatMap(resolveCountry)
        if let resolvedCity {
            if resolvedCountry == nil {
                resolvedCountry = country(for: resolvedCity)
            }
            return (resolvedCity.nameRu, resolvedCountry?.nameRu)
        }
        if let resolvedCountry {
            return (rawCity?.nilIfBlank, resolvedCountry.nameRu)
        }
        return (rawCity?.nilIfBlank, rawCountry?.nilIfBlank)
    }

    private static func bundledURL() -> URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "GeoData", withExtension: "json") {
            return url
        }
        #endif
        let tokenBundle = Bundle(for: BundleToken.self)
        if let url = tokenBundle.url(forResource: "GeoData", withExtension: "json") {
            return url
        }
        return Bundle.main.url(forResource: "GeoData", withExtension: "json")
    }

    private static func makeTerms(
        countryRecords: [CountryRecord],
        cityRecords: [CityRecord],
        countries: [Country],
        cities: [City]
    ) -> [SearchTerm] {
        var terms: [SearchTerm] = []
        for (index, record) in cityRecords.enumerated() {
            let city = cities[index]
            var seen: Set<String> = []
            func add(_ text: String, caseSensitive: Bool) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 3 else { return }
                let key = (caseSensitive ? "c:" : "i:") + trimmed
                guard seen.insert(key).inserted else { return }
                terms.append(SearchTerm(text: trimmed, caseSensitive: caseSensitive, city: city, country: nil))
            }
            add(record.ru, caseSensitive: false)
            add(record.en, caseSensitive: record.enSensitive ?? false)
            record.aliases.forEach { add($0, caseSensitive: false) }
            record.caseAliases.forEach { add($0, caseSensitive: true) }
        }
        for (index, record) in countryRecords.enumerated() {
            let country = countries[index]
            var seen: Set<String> = []
            func add(_ text: String, caseSensitive: Bool) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 3 else { return }
                let key = (caseSensitive ? "c:" : "i:") + trimmed
                guard seen.insert(key).inserted else { return }
                terms.append(SearchTerm(text: trimmed, caseSensitive: caseSensitive, city: nil, country: country))
            }
            add(record.ru, caseSensitive: false)
            add(record.en, caseSensitive: record.enSensitive ?? false)
            record.aliases.forEach { add($0, caseSensitive: false) }
            record.caseAliases.forEach { add($0, caseSensitive: true) }
        }
        return terms.sorted { lhs, rhs in
            if lhs.text.count != rhs.text.count { return lhs.text.count > rhs.text.count }
            let lhsCity = lhs.city != nil
            let rhsCity = rhs.city != nil
            if lhsCity != rhsCity { return lhsCity && !rhsCity }
            return lhs.text < rhs.text
        }
    }

    private static func ranges(of needle: String, in text: String, caseSensitive: Bool) -> [Range<String.Index>] {
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive, .diacriticInsensitive]
        var found: [Range<String.Index>] = []
        var search = text.startIndex..<text.endIndex
        while let range = text.range(of: needle, options: options, range: search) {
            if isBoundary(text, range) {
                found.append(range)
            }
            guard range.lowerBound < text.endIndex else { break }
            let next = text.index(after: range.lowerBound)
            if next >= text.endIndex { break }
            search = next..<text.endIndex
        }
        return found
    }

    private static func isBoundary(_ text: String, _ range: Range<String.Index>) -> Bool {
        if range.lowerBound > text.startIndex {
            let previous = text[text.index(before: range.lowerBound)]
            if previous.isLetter || previous.isNumber { return false }
        }
        if range.upperBound < text.endIndex {
            let next = text[range.upperBound]
            if next.isLetter || next.isNumber { return false }
        }
        return true
    }
}

struct CountryRecord: Decodable {
    var id: String
    var ru: String
    var en: String
    var aliases: [String]
    var caseAliases: [String]
    var enSensitive: Bool?
}

struct CityRecord: Decodable {
    var id: String
    var country: String
    var ru: String
    var en: String
    var aliases: [String]
    var caseAliases: [String]
    var enSensitive: Bool?
}

private struct GeoFile: Decodable {
    var countries: [CountryRecord]
    var cities: [CityRecord]
}

private struct SearchTerm {
    var text: String
    var caseSensitive: Bool
    var city: City?
    var country: Country?
}

private final class BundleToken: NSObject {}
