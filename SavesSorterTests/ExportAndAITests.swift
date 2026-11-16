import XCTest
#if SWIFT_PACKAGE
@testable import SavesSorterCore
#endif

final class ExportAndAITests: XCTestCase {
    func testCSVEscapingAndAddress() {
        let entry = LibraryEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            postId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            kind: .visit,
            title: "Кафе \"X\"",
            city: "Рим",
            country: "Италия",
            note: "вид, море",
            instagramURL: "https://www.instagram.com/p/AAA/",
            needsReview: false,
            confidence: 0.9,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let csv = ExportService.csv(entries: [entry])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}Name,Address,City,Country,Note,Instagram link\n"), csv)
        XCTAssertTrue(csv.contains("\"Кафе \"\"X\"\"\""), csv)
        XCTAssertTrue(csv.contains("\"Кафе \"\"X\"\", Рим, Италия\""), csv)
        XCTAssertTrue(csv.contains("\"вид, море\""), csv)
        XCTAssertTrue(csv.contains("https://www.instagram.com/p/AAA/"), csv)
    }

    func testBuyNamesListAndMapQuery() {
        let entry = LibraryEntry(
            postId: UUID(),
            kind: .buy,
            title: "керамика",
            shop: "İznik Works",
            city: "Стамбул",
            country: "Турция",
            instagramURL: "https://www.instagram.com/p/BBB/",
            needsReview: false,
            confidence: 0.9
        )
        XCTAssertEqual(ExportService.namesList(entries: [entry]), "керамика — İznik Works")
        let url = MapsLink.url(for: entry)
        XCTAssertEqual(url?.host, "www.google.com")
        XCTAssertTrue(url?.query?.contains("api=1") ?? false)
        XCTAssertTrue(url?.absoluteString.contains("query=") ?? false)
        let query = URLComponents(url: url!, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "query" }?
            .value
        XCTAssertEqual(query, "İznik Works, Стамбул, Турция")
    }

    func testAIJSONParsesWhereAndCanonicalizesCountry() throws {
        let raw = """
        ```json
        {"category":"both","places":[{"name":"Лувр","city":"Париж","country":"France"}],"items":[{"what":"сумка","where":"Zara","city":"Париж","country":null}]}
        ```
        """
        let payload = try XCTUnwrap(AIResponseParser.parse(text: raw))
        XCTAssertEqual(payload.category, "both")
        XCTAssertEqual(payload.places.first?.name, "Лувр")
        XCTAssertEqual(payload.items.first?.shop, "Zara")
        XCTAssertEqual(payload.items.first?.what, "сумка")
        let lexicon = try GeoLexicon.loadBundled()
        let drafts = AIResponseParser.drafts(from: payload, lexicon: lexicon)
        let visit = drafts.first { $0.kind == .visit }
        XCTAssertEqual(visit?.city, "Париж")
        XCTAssertEqual(visit?.country, "Франция")
        XCTAssertEqual(visit?.needsReview, false)
        let buy = drafts.first { $0.kind == .buy }
        XCTAssertEqual(buy?.shop, "Zara")
        XCTAssertEqual(buy?.city, "Париж")
        XCTAssertEqual(buy?.country, "Франция")
    }

    func testGroupingAndMerge() throws {
        let post = SavedPost(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            instagramURL: "https://www.instagram.com/p/AAA/",
            shortcode: "AAA",
            mediaKind: .post,
            status: .sorted
        )
        let otherPost = SavedPost(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            instagramURL: "https://www.instagram.com/p/BBB/",
            shortcode: "BBB",
            mediaKind: .post,
            status: .sorted
        )
        func entry(_ title: String, city: String, country: String, kind: EntryKind, post: SavedPost, review: Bool = false) -> LibraryEntry {
            LibraryEntry(
                postId: post.id,
                kind: kind,
                title: title,
                city: city,
                country: country,
                instagramURL: post.instagramURL,
                needsReview: review,
                confidence: 0.8
            )
        }
        let beijing = entry("Запретный город", city: "Пекин", country: "Китай", kind: .visit, post: post)
        let shanghaiBuy = entry("шёлк", city: "Шанхай", country: "Китай", kind: .buy, post: post)
        let loose = entry("тренч", city: "", country: "", kind: .buy, post: post, review: true)
        let groups = LibraryGrouping.countries(from: [beijing, shanghaiBuy, loose])
        XCTAssertEqual(groups.map(\.country), ["Китай"])
        XCTAssertEqual(Set(groups[0].cities.map(\.city)), ["Пекин", "Шанхай"])
        XCTAssertEqual(LibraryGrouping.withoutCity([beijing, loose]).count, 1)

        let base = Library(posts: [post], entries: [beijing])
        let incomingEntry = entry("Набережная", city: "Шанхай", country: "Китай", kind: .visit, post: otherPost)
        let duplicate = entry("Запретный город", city: "Пекин", country: "Китай", kind: .visit, post: post)
        let incoming = Library(posts: [otherPost, post], entries: [incomingEntry, duplicate])
        let merged = LibraryMerge.merge(base: base, incoming: incoming)
        XCTAssertEqual(merged.posts.map(\.shortcode).sorted(), ["AAA", "BBB"])
        XCTAssertEqual(merged.entries.count, 2)
        XCTAssertTrue(merged.entries.contains { $0.title == "Набережная" && $0.postId == otherPost.id })
    }

    func testLibraryRoundTrip() throws {
        let library = Library(
            posts: [
                SavedPost(
                    instagramURL: "https://www.instagram.com/reel/Ab1/",
                    shortcode: "Ab1",
                    mediaKind: .reel,
                    status: .failed,
                    failureCode: .placesInVideo,
                    caption: "места в видео"
                ),
            ]
        )
        let data = try LibraryCoding.encode(library)
        let decoded = try LibraryCoding.decode(data)
        XCTAssertEqual(decoded.posts.count, 1)
        XCTAssertEqual(decoded.posts[0].shortcode, "Ab1")
        XCTAssertEqual(decoded.posts[0].failureCode, .placesInVideo)
        XCTAssertEqual(decoded.posts[0].mediaKind, .reel)
    }
}

enum TestResources {
    static func string(name: String, ext: String) throws -> String {
        let bundle = resourceBundle()
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw NSError(domain: "TestResources", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Missing \(name).\(ext)",
            ])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func resourceBundle() -> Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle(for: CaptionParserTests.self)
        #endif
    }
}
