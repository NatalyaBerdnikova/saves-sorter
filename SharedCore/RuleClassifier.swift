import Foundation

struct RuleClassifier {
    var lexicon: GeoLexicon

    func classify(_ caption: String) -> ClassificationResult {
        let text = caption.replacingOccurrences(of: "\r\n", with: "\n").cleanedCaption
        if text.isEmpty {
            return ClassificationResult(entries: [], nothingUseful: true, nothingReason: .noSignals)
        }

        let geo = lexicon.matches(in: text)
        let lines = splitLines(text)
        let shopping = KeywordScanner.shopping(in: text)
        let contentIsElsewhere = KeywordScanner.contentIsElsewhere(text)

        var contextCity: City?
        var contextCountry: Country?
        var places: [RawPlace] = []
        var whats: [LocatedText] = []
        var shops: [LocatedText] = []

        for line in lines {
            let lineMatches = geo.filter { line.range.overlaps($0.range) }
            updateContext(lineMatches, city: &contextCity, country: &contextCountry)
            let location = LocatedContext(city: contextCity, country: contextCountry)

            if let what = firstRefined(KeywordScanner.captures(phrases: KeywordScanner.whatPhrases, in: line.text), refine: refineWhat) {
                whats.append(LocatedText(text: what, context: location))
            }
            for raw in KeywordScanner.captures(phrases: KeywordScanner.shopPhrases, in: line.text) {
                if let shop = refineShop(raw) {
                    shops.append(LocatedText(text: shop, context: location))
                }
            }

            if isGeoOnly(line: line, matches: lineMatches, in: text) { continue }
            for chunk in placeChunks(in: line.text) {
                guard let name = cleanPlaceName(chunk.text) else { continue }
                places.append(RawPlace(name: name, source: chunk.source, context: location))
            }
        }

        var drafts = assemble(
            places: places,
            whats: whats,
            shops: shops,
            shopping: shopping.points >= 2,
            strongShopping: shopping.strong
        )

        let documentCities = lexicon.uniqueCities(in: text)
        if documentCities.count == 1, let only = documentCities.first {
            let countryName = lexicon.country(for: only)?.nameRu
            for index in drafts.indices where (drafts[index].city ?? "").isEmpty {
                drafts[index].city = only.nameRu
                if (drafts[index].country ?? "").isEmpty {
                    drafts[index].country = countryName
                }
            }
        }

        if drafts.isEmpty, !contentIsElsewhere, documentCities.count == 1, leftoverLetters(afterRemovingGeoAndTags: text, matches: geo) < 12,
           let only = documentCities.first {
            drafts.append(
                makeVisit(
                    title: only.nameRu,
                    context: LocatedContext(city: only, country: lexicon.country(for: only)),
                    source: .cityOnly,
                    strongShopping: false
                )
            )
        }

        drafts = dedupe(drafts)
        if drafts.isEmpty {
            return ClassificationResult(
                entries: [],
                nothingUseful: true,
                nothingReason: contentIsElsewhere ? .placesInVideo : .noSignals
            )
        }
        return ClassificationResult(entries: drafts, nothingUseful: false, nothingReason: nil)
    }

    private func assemble(
        places: [RawPlace],
        whats: [LocatedText],
        shops: [LocatedText],
        shopping: Bool,
        strongShopping: Bool
    ) -> [DraftEntry] {
        if !shopping {
            return places.map { makeVisit(title: $0.name, context: $0.context, source: $0.source, strongShopping: false) }
        }

        var entries: [DraftEntry] = []
        let landmarks = places.filter { LandmarkList.isLandmark($0.name) }
        let shopPlaces = places.filter { !LandmarkList.isLandmark($0.name) }
        entries.append(contentsOf: landmarks.map {
            makeVisit(title: $0.name, context: $0.context, source: $0.source, strongShopping: strongShopping)
        })

        var shopItems: [LocatedText] = shops
        for place in shopPlaces {
            shopItems.append(LocatedText(text: place.name, context: place.context))
        }
        shopItems = dedupeLocated(shopItems)

        let what = whats.first
        if shopItems.isEmpty {
            if let what {
                entries.append(makeBuy(title: what.text, shop: nil, context: what.context, strongShopping: strongShopping))
            }
        } else {
            for shop in shopItems {
                let context = shop.context.city == nil ? (what?.context ?? shop.context) : shop.context
                let title = what?.text ?? shop.text
                entries.append(makeBuy(title: title, shop: shop.text, context: context, strongShopping: strongShopping))
            }
        }
        return entries
    }

    private func makeVisit(title: String, context: LocatedContext, source: PlaceSource, strongShopping: Bool) -> DraftEntry {
        var score = 0.0
        switch source {
        case .pin: score += 0.4
        case .bullet: score += 0.25
        case .quote: score += 0.3
        case .cityOnly: score += 0.2
        }
        let hasCity = context.city != nil
        if hasCity { score += 0.3 }
        if context.country != nil { score += 0.15 }
        if wordCount(title) <= 6 { score += 0.1 }
        return DraftEntry(
            kind: .visit,
            title: title,
            shop: nil,
            city: context.city?.nameRu,
            country: context.country?.nameRu,
            needsReview: !hasCity || score < 0.7,
            confidence: min(score, 1)
        )
    }

    private func makeBuy(title: String, shop: String?, context: LocatedContext, strongShopping: Bool) -> DraftEntry {
        var score = 0.0
        let hasCity = context.city != nil
        if hasCity { score += 0.35 }
        if context.country != nil { score += 0.15 }
        if let shop, !shop.isEmpty { score += 0.2 }
        if title.count >= 3 { score += 0.2 }
        if strongShopping { score += 0.1 }
        let storedShop = shop.flatMap { $0.caseInsensitiveCompare(title) == .orderedSame ? $0 : $0 }
        return DraftEntry(
            kind: .buy,
            title: title,
            shop: storedShop?.nilIfBlank,
            city: context.city?.nameRu,
            country: context.country?.nameRu,
            needsReview: !hasCity || score < 0.7,
            confidence: min(score, 1)
        )
    }

    private func updateContext(_ matches: [GeoMatch], city: inout City?, country: inout Country?) {
        var lineCities: [City] = []
        var explicitCountries: [Country] = []
        for match in matches {
            if let found = match.city, !lineCities.contains(where: { $0.id == found.id }) {
                lineCities.append(found)
            } else if match.city == nil, let found = match.country, !explicitCountries.contains(where: { $0.id == found.id }) {
                explicitCountries.append(found)
            }
        }
        if lineCities.count == 1, let found = lineCities.first {
            city = found
            country = lexicon.country(for: found) ?? country
        } else if lineCities.count > 1 {
            city = nil
            if let shared = sharedCountry(of: lineCities) {
                country = shared
            }
        } else if explicitCountries.count == 1, let found = explicitCountries.first {
            country = found
            if let current = city, lexicon.country(for: current)?.id != found.id {
                city = nil
            }
        }
    }

    private func sharedCountry(of cities: [City]) -> Country? {
        let ids = Set(cities.map(\.countryId))
        guard ids.count == 1, let id = ids.first else { return nil }
        return lexicon.countries.first { $0.id == id }
    }

    private func isGeoOnly(line: LineSlice, matches: [GeoMatch], in text: String) -> Bool {
        leftoverLetters(in: line, matches: matches, text: text) < 2
    }

    private func leftoverLetters(in line: LineSlice, matches: [GeoMatch], text: String) -> Int {
        var kept = ""
        var cursor = line.range.lowerBound
        let sorted = matches.sorted { $0.range.lowerBound < $1.range.lowerBound }
        for match in sorted {
            let from = max(cursor, match.range.lowerBound)
            if cursor < from, from <= line.range.upperBound {
                let pieceEnd = min(from, line.range.upperBound)
                if cursor < pieceEnd {
                    kept.append(contentsOf: text[cursor..<pieceEnd])
                }
            }
            cursor = max(cursor, min(match.range.upperBound, line.range.upperBound))
        }
        if cursor < line.range.upperBound {
            kept.append(contentsOf: text[cursor..<line.range.upperBound])
        }
        kept = kept.replacingOccurrences(of: "#[\\p{L}\\p{N}_]+", with: " ", options: .regularExpression)
        return kept.filter(\.isLetter).count
    }

    private func leftoverLetters(afterRemovingGeoAndTags text: String, matches: [GeoMatch]) -> Int {
        let whole = LineSlice(text: text, range: text.startIndex..<text.endIndex)
        return leftoverLetters(in: whole, matches: matches, text: text)
    }

    private func placeChunks(in line: String) -> [(text: String, source: PlaceSource)] {
        if containsPin(line) {
            return splitPins(line).map { (text: $0, source: .pin) }
        }
        if let bullet = bulletContent(line), wordCount(bullet) <= 8, bullet.count <= 80 {
            return [(bullet, .bullet)]
        }
        return quoted(line)
            .filter { wordCount($0) <= 8 && $0.count <= 80 }
            .map { ($0, .quote) }
    }

    private func cleanPlaceName(_ raw: String) -> String? {
        var text = stripTags(raw)
        let hits = lexicon.matches(in: text).sorted { $0.range.lowerBound > $1.range.lowerBound }
        for hit in hits where text.indices.contains(hit.range.lowerBound) {
            text.removeSubrange(hit.range)
        }
        text = stripLeadingShopLabel(text)
        text = trimEdge(text)
        let letters = text.filter(\.isLetter)
        guard letters.count >= 2 else { return nil }
        if lexicon.resolveCity(text) != nil && leftoverLetters(afterRemovingGeoAndTags: text, matches: lexicon.matches(in: text)) < 2 {
            return nil
        }
        if let country = lexicon.resolveCountry(text), country.nameRu.caseInsensitiveCompare(text) == .orderedSame {
            return nil
        }
        return text
    }

    private func refineWhat(_ raw: String) -> String? {
        var text = clipClause(raw)
        text = cutMetaComma(text)
        text = stripGeoAndTrailingPrepositions(text)
        text = trimEdge(text)
        guard text.filter(\.isLetter).count >= 3 else { return nil }
        if text.count > 80 {
            text = String(text.prefix(80)).trimmingCharacters(in: .whitespaces)
        }
        return text.nilIfBlank
    }

    private func refineShop(_ raw: String) -> String? {
        var text = clipClause(raw)
        text = stripLeadingShopLabel(text)
        text = stripGeoAndTrailingPrepositions(text)
        text = trimEdge(text)
        guard text.filter(\.isLetter).count >= 2, wordCount(text) <= 8, text.count <= 60 else { return nil }
        if leftoverLetters(afterRemovingGeoAndTags: text, matches: lexicon.matches(in: text)) < 2 {
            return nil
        }
        return text
    }

    private func stripGeoAndTrailingPrepositions(_ raw: String) -> String {
        var text = raw
        let hits = lexicon.matches(in: text).sorted { $0.range.lowerBound > $1.range.lowerBound }
        for hit in hits {
            text.removeSubrange(hit.range)
        }
        let prepositions: Set<String> = ["в", "во", "на", "из", "от", "к", "с", "у", "по", "in", "at", "of", "from", "near", "to"]
        var changed = true
        while changed {
            changed = false
            text = trimEdge(text)
            let parts = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let last = parts.last else { break }
            if prepositions.contains(where: { $0.caseInsensitiveCompare(last) == .orderedSame }) {
                text = parts.dropLast().joined(separator: " ")
                changed = true
            }
        }
        return text
    }

    private func firstRefined(_ values: [String], refine: (String) -> String?) -> String? {
        for value in values {
            if let refined = refine(value) { return refined }
        }
        return nil
    }

    private func dedupe(_ entries: [DraftEntry]) -> [DraftEntry] {
        var seen: Set<String> = []
        var result: [DraftEntry] = []
        for entry in entries {
            let key = [
                entry.kind.rawValue,
                fold(entry.title),
                fold(entry.shop ?? ""),
                fold(entry.city ?? ""),
            ].joined(separator: "|")
            if seen.insert(key).inserted {
                result.append(entry)
            }
        }
        return result
    }

    private func dedupeLocated(_ items: [LocatedText]) -> [LocatedText] {
        var seen: Set<String> = []
        var result: [LocatedText] = []
        for item in items {
            let key = fold(item.text) + "|" + (item.context.city?.id ?? "")
            if seen.insert(key).inserted { result.append(item) }
        }
        return result
    }

    private func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
    }
}

private struct LineSlice {
    var text: String
    var range: Range<String.Index>
}

private struct LocatedContext {
    var city: City?
    var country: Country?
}

private struct LocatedText {
    var text: String
    var context: LocatedContext
}

private struct RawPlace {
    var name: String
    var source: PlaceSource
    var context: LocatedContext
}

private enum PlaceSource {
    case pin
    case bullet
    case quote
    case cityOnly
}

private enum LandmarkList {
    private static let stems = [
        "башн", "музей", "парк", "собор", "мечет", "дворец", "набереж", "площад", "мост", "храм",
        "церков", "замок", "галере", "смотров", "пляж", "водопад", "крепост", "cathedral", "museum",
        "tower", "palace", "bridge", "square", "beach", "temple", "kulesi", "kule", "mosque", "castle", "gallery",
    ]

    static func isLandmark(_ name: String) -> Bool {
        let words = name.split { !$0.isLetter }.map(String.init)
        for stem in stems {
            for word in words {
                if word.range(of: stem, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil {
                    return true
                }
            }
        }
        return false
    }
}

private enum KeywordScanner {
    static let whatPhrases = [
        "где купить", "where to buy", "купила", "купили", "купил", "купить",
    ]
    static let shopPhrases = [
        "магазинчик", "магазин", "шоурум", "лавка", "mağaza", "shop", "store",
    ]

    static func shopping(in text: String) -> (points: Int, strong: Bool) {
        let phrases: [(String, Int, Bool)] = [
            ("где купить", 2, true),
            ("where to buy", 2, true),
            ("артикул", 2, true),
            ("промокод", 2, true),
            ("магазинчик", 2, true),
            ("магазин", 2, true),
            ("шоурум", 2, true),
            ("mağaza", 2, true),
            ("shop", 2, true),
            ("store", 2, true),
            ("купить", 1, false),
            ("купила", 1, false),
            ("купили", 1, false),
            ("купил", 1, false),
            ("цена", 1, false),
            ("цену", 1, false),
            ("цены", 1, false),
            ("цене", 1, false),
            ("price", 1, false),
            ("скидка", 1, false),
            ("скидки", 1, false),
            ("скидку", 1, false),
            ("шопинг", 1, false),
            ("шопинга", 1, false),
            ("shopping", 1, false),
            ("alışveriş", 1, false),
            ("wildberries", 1, false),
            ("ozon", 1, false),
            ("озон", 1, false),
            ("ссылка в шапке", 1, false),
            ("ссылка в профиле", 1, false),
            ("link in bio", 1, false),
            ("₽", 1, false),
            ("руб", 1, false),
        ].sorted { $0.0.count > $1.0.count }

        var occupied: [Range<String.Index>] = []
        var points = 0
        var strong = false
        for phrase in phrases {
            for range in ranges(of: phrase.0, in: text) {
                if occupied.contains(where: { $0.overlaps(range) }) { continue }
                occupied.append(range)
                points += phrase.1
                if phrase.2 { strong = true }
            }
        }
        return (points, strong)
    }

    static func contentIsElsewhere(_ text: String) -> Bool {
        let markers = [
            "в видео", "смотри видео", "смотрите видео", "см. видео", "см видео",
            "в ролике", "локации в видео", "места в видео", "список в видео",
            "places in the video", "in the video", "in this video", "see the video",
            "watch the video", "only in the video",
            "ссылка в шапке", "ссылка в профиле", "ссылка в био", "link in bio",
        ]
        return markers.contains { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    static func captures(phrases: [String], in text: String) -> [String] {
        let sorted = phrases.sorted { $0.count > $1.count }
        var occupied: [Range<String.Index>] = []
        var found: [(Range<String.Index>, String)] = []
        for phrase in sorted {
            for range in ranges(of: phrase, in: text) {
                if occupied.contains(where: { $0.overlaps(range) }) { continue }
                occupied.append(range)
                found.append((range, String(text[range.upperBound...])))
            }
        }
        return found.sorted { $0.0.lowerBound < $1.0.lowerBound }.map(\.1)
    }

    private static func ranges(of needle: String, in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var search = text.startIndex..<text.endIndex
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        while let range = text.range(of: needle, options: options, range: search) {
            if isBoundary(text, range) || needle == "₽" {
                found.append(range)
            }
            guard let next = text.index(range.lowerBound, offsetBy: 1, limitedBy: text.endIndex), next < text.endIndex else { break }
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

private func splitLines(_ text: String) -> [LineSlice] {
    var lines: [LineSlice] = []
    var start = text.startIndex
    while start <= text.endIndex {
        let end = text[start...].firstIndex(of: "\n") ?? text.endIndex
        let slice = String(text[start..<end])
        if !slice.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append(LineSlice(text: slice, range: start..<end))
        }
        if end == text.endIndex { break }
        start = text.index(after: end)
    }
    return lines
}

private func containsPin(_ line: String) -> Bool {
    line.contains { isPin($0) }
}

private func isPin(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
        scalar.value == 0x1F4CD || scalar.value == 0x1F4CC || scalar.value == 0x1F5FA
    }
}

private func splitPins(_ line: String) -> [String] {
    var parts: [String] = []
    var current = ""
    for character in line {
        if isPin(character) {
            if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                parts.append(current)
            }
            current = ""
        } else {
            current.append(character)
        }
    }
    if !current.trimmingCharacters(in: .whitespaces).isEmpty {
        parts.append(current)
    }
    return parts
}

private func bulletContent(_ line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if let index = trimmed.firstIndex(where: { $0 == "•" || $0 == "–" || $0 == "—" || $0 == "-" || $0 == "*" }) , index == trimmed.startIndex {
        let rest = trimmed[trimmed.index(after: index)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }
    var index = trimmed.startIndex
    guard index < trimmed.endIndex, trimmed[index].isNumber else { return nil }
    while index < trimmed.endIndex, trimmed[index].isNumber {
        index = trimmed.index(after: index)
    }
    guard index < trimmed.endIndex, trimmed[index] == "." || trimmed[index] == ")" else { return nil }
    let rest = trimmed[trimmed.index(after: index)...].trimmingCharacters(in: .whitespaces)
    return rest.isEmpty ? nil : rest
}

private func quoted(_ line: String) -> [String] {
    between(line, open: "«", close: "»") + between(line, open: "“", close: "”") + between(line, open: "\"", close: "\"")
}

private func between(_ text: String, open: Character, close: Character) -> [String] {
    var result: [String] = []
    var current: String?
    for character in text {
        if current == nil {
            if character == open { current = "" }
        } else if character == close {
            if let value = current?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                result.append(value)
            }
            current = nil
        } else {
            current?.append(character)
        }
    }
    return result
}

private func stripTags(_ text: String) -> String {
    text.replacingOccurrences(of: "#[\\p{L}\\p{N}_]+", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "@[A-Za-z0-9._]+", with: " ", options: .regularExpression)
}

private func stripLeadingShopLabel(_ text: String) -> String {
    let labels = ["магазинчик", "магазин", "шоурум", "лавка", "mağaza", "shop", "store"]
    var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var changed = true
    while changed {
        changed = false
        for label in labels {
            if let range = result.range(of: label, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) {
                let next = range.upperBound
                if next == result.endIndex || !result[next].isLetter {
                    result = String(result[next...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                    break
                }
            }
        }
    }
    return result
}

private func clipClause(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let stop = text.firstIndex(where: { $0.isNewline || $0 == "#" || isPin($0) }) {
        text = String(text[..<stop])
    }
    if let dot = text.firstIndex(of: ".") {
        let after = text.index(after: dot)
        if after == text.endIndex || text[after].isWhitespace {
            text = String(text[..<dot])
        }
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func cutMetaComma(_ text: String) -> String {
    guard let comma = text.firstIndex(of: ",") else { return text }
    let tail = text[text.index(after: comma)...].trimmingCharacters(in: .whitespacesAndNewlines)
    let markers = ["артикул", "арт", "цена", "цену", "цены", "price", "промокод", "размер", "₽", "руб"]
    let startsMeta = markers.contains { marker in
        tail.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
    }
    return startsMeta ? String(text[..<comma]) : text
}

private func trimEdge(_ text: String) -> String {
    let punctuation = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)
    var scalars = text.unicodeScalars
    while let first = scalars.first, punctuation.contains(first) || first.value == 0xFE0F {
        scalars.removeFirst()
    }
    while let last = scalars.last, punctuation.contains(last) || last.value == 0xFE0F {
        scalars.removeLast()
    }
    let collapsed = String(scalars).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    return collapsed
}

private func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace }).count
}
