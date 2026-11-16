import XCTest
#if SWIFT_PACKAGE
@testable import SavesSorterCore
#endif

final class RuleClassifierTests: XCTestCase {
    private var lexicon: GeoLexicon!
    private var classifier: RuleClassifier!

    override func setUp() {
        super.setUp()
        lexicon = try! GeoLexicon.loadBundled()
        classifier = RuleClassifier(lexicon: lexicon)
    }

    func testLexiconDeclensionsAndCase() {
        XCTAssertEqual(lexicon.resolveCity("Стамбуле")?.nameRu, "Стамбул")
        XCTAssertEqual(lexicon.resolveCity("Istanbul")?.nameRu, "Стамбул")
        XCTAssertEqual(lexicon.country(for: lexicon.resolveCity("Стамбул")!)?.nameRu, "Турция")
        XCTAssertEqual(lexicon.resolveCountry("во Франции")?.nameRu, "Франция")
        XCTAssertEqual(lexicon.resolveCity("Nice")?.nameRu, "Ницца")
        XCTAssertNil(lexicon.resolveCity("nice cafe"))
        XCTAssertNil(lexicon.resolveCity("Парижский"))
        XCTAssertEqual(lexicon.resolveCity("в Пекине")?.nameRu, "Пекин")
        XCTAssertEqual(lexicon.resolveCity("Shanghai")?.nameRu, "Шанхай")
    }

    func testIstanbulPinsWithDeclension() {
        let caption = """
        Лучшие места в Стамбуле

        📍 Кафе Mandabatmaz
        📍 Галатская башня
        """
        let result = classifier.classify(caption)
        XCTAssertFalse(result.nothingUseful, result.description)
        assertVisit(result, title: "Кафе Mandabatmaz", city: "Стамбул", country: "Турция", review: false)
        assertVisit(result, title: "Галатская башня", city: "Стамбул", country: "Турция", review: false)
        XCTAssertEqual(result.entries.count, 2, result.description)
    }

    func testChinaTwoCities() {
        let caption = """
        Китай

        Пекин
        📍 Запретный город

        Шанхай
        📍 Набережная Вайтань
        """
        let result = classifier.classify(caption)
        assertVisit(result, title: "Запретный город", city: "Пекин", country: "Китай", review: false)
        assertVisit(result, title: "Набережная Вайтань", city: "Шанхай", country: "Китай", review: false)
    }

    func testShoppingWithCity() {
        let caption = """
        Где купить керамику в Стамбуле

        Магазин: İznik Works
        Цена около 1500 лир
        """
        let result = classifier.classify(caption)
        XCTAssertEqual(result.entries.count, 1, result.description)
        let item = result.entries[0]
        XCTAssertEqual(item.kind, .buy)
        XCTAssertEqual(item.title, "керамику")
        XCTAssertEqual(item.shop, "İznik Works")
        XCTAssertEqual(item.city, "Стамбул")
        XCTAssertEqual(item.country, "Турция")
        XCTAssertFalse(item.needsReview, result.description)
    }

    func testShoppingWithoutCityNeedsReview() {
        let caption = "Где купить классный тренч, артикул WB-123, цена 8900 ₽"
        let result = classifier.classify(caption)
        XCTAssertEqual(result.entries.count, 1, result.description)
        let item = result.entries[0]
        XCTAssertEqual(item.kind, .buy)
        XCTAssertEqual(item.title, "классный тренч")
        XCTAssertNil(item.city)
        XCTAssertTrue(item.needsReview)
        XCTAssertFalse(result.nothingUseful)
    }

    func testPlacesOnlyInVideo() {
        let caption = "Сохраняю, потому что красиво. Все места в видео! Смотрите видео."
        let result = classifier.classify(caption)
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertTrue(result.nothingUseful)
        XCTAssertEqual(result.nothingReason, .placesInVideo)
    }

    func testEmptyCaption() {
        let result = classifier.classify("   \n")
        XCTAssertTrue(result.nothingUseful)
        XCTAssertEqual(result.nothingReason, .noSignals)
        XCTAssertTrue(result.entries.isEmpty)
    }

    func testEnglishFlorenceShopping() {
        let caption = """
        Where to buy leather bags in Florence.
        Shop: Scuola del Cuoio
        Price: 250 euro
        """
        let result = classifier.classify(caption)
        XCTAssertEqual(result.entries.count, 1, result.description)
        let item = result.entries[0]
        XCTAssertEqual(item.kind, .buy)
        XCTAssertEqual(item.title, "leather bags")
        XCTAssertEqual(item.shop, "Scuola del Cuoio")
        XCTAssertEqual(item.city, "Флоренция")
        XCTAssertEqual(item.country, "Италия")
        XCTAssertFalse(item.needsReview, result.description)
    }

    func testTurkishIstanbulPins() {
        let caption = """
        İstanbul'da gezilecek yerler
        📍 Galata Kulesi
        📍 Yerebatan Sarnıcı
        """
        let result = classifier.classify(caption)
        assertVisit(result, title: "Galata Kulesi", city: "Стамбул", country: "Турция", review: false)
        assertVisit(result, title: "Yerebatan Sarnıcı", city: "Стамбул", country: "Турция", review: false)
    }

    func testParisHashtagsAndPin() {
        let caption = """
        A day in Paris #paris #france
        📍 Louvre Museum
        """
        let result = classifier.classify(caption)
        assertVisit(result, title: "Louvre Museum", city: "Париж", country: "Франция", review: false)
    }

    func testNiceAdjectiveDoesNotMatchCity() {
        let caption = """
        a nice day in Rome
        📍 Colosseum
        """
        let result = classifier.classify(caption)
        assertVisit(result, title: "Colosseum", city: "Рим", country: "Италия", review: false)
        XCTAssertFalse(result.entries.contains { $0.city == "Ницца" })
    }

    func testFrancePinWithoutCityNeedsReview() {
        let caption = """
        Любимые места во Франции
        📍 Лувр
        """
        let result = classifier.classify(caption)
        assertVisit(result, title: "Лувр", city: nil, country: "Франция", review: true)
    }

    func testQuotedPlaceInIstanbul() {
        let caption = "Обязательно зайдите в «Галатская башня», это в Стамбуле."
        let result = classifier.classify(caption)
        assertVisit(result, title: "Галатская башня", city: "Стамбул", country: "Турция", review: false)
    }

    func testShoppingAndLandmarkSplit() {
        let caption = """
        Стамбул: и погулять, и купить керамику

        📍 Галатская башня
        📍 Магазин İznik Works
        Где купить керамику
        """
        let result = classifier.classify(caption)
        assertVisit(result, title: "Галатская башня", city: "Стамбул", country: "Турция", review: false)
        let buy = result.entries.first { $0.kind == .buy }
        XCTAssertNotNil(buy, result.description)
        XCTAssertEqual(buy?.title, "керамику")
        XCTAssertEqual(buy?.shop, "İznik Works")
        XCTAssertEqual(buy?.city, "Стамбул")
        XCTAssertFalse(buy?.needsReview ?? true)
    }

    func testParisInsideLongerWordDoesNotMatch() {
        let result = classifier.classify("Парижский круассан просто вкусный, без адреса")
        XCTAssertTrue(result.entries.isEmpty, result.description)
        XCTAssertEqual(result.nothingReason, .noSignals)
    }

    private func assertVisit(
        _ result: ClassificationResult,
        title: String,
        city: String?,
        country: String?,
        review: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let matches = result.entries.filter { $0.kind == .visit && $0.title == title }
        XCTAssertEqual(matches.count, 1, result.description, file: file, line: line)
        guard let entry = matches.first else { return }
        XCTAssertEqual(entry.city, city, result.description, file: file, line: line)
        XCTAssertEqual(entry.country, country, result.description, file: file, line: line)
        XCTAssertEqual(entry.needsReview, review, result.description, file: file, line: line)
    }
}
