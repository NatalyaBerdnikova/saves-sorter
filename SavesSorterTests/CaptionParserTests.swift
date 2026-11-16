import XCTest
#if SWIFT_PACKAGE
@testable import SavesSorterCore
#endif

final class CaptionParserTests: XCTestCase {
    func testDescriptionMetaExtractsCaptionAuthorAndImage() {
        let html = """
        <html><head>
        <meta name="description" content="123 likes, 4 comments - maria on November 2, 2024: &quot;📍 Кафе Mandabatmaz&quot;." />
        <meta property="og:title" content="Maria on Instagram: &quot;📍 Кафе Mandabatmaz&quot;" />
        <meta property="og:image" content="https://example.com/cover.jpg" />
        </head></html>
        """
        let parsed = CaptionParser.parse(pageHTML: html, embedHTML: nil)
        XCTAssertEqual(parsed.caption, "📍 Кафе Mandabatmaz")
        XCTAssertEqual(parsed.author, "maria")
        XCTAssertEqual(parsed.imageURL, "https://example.com/cover.jpg")
        XCTAssertEqual(parsed.captionSource, .metaDescription)
        XCTAssertFalse(parsed.isUnavailable)
    }

    func testDescriptionAttributeOrderAndEntities() {
        let html = """
        <meta content="10 likes, 2 comments - anna on May 1, 2024: &quot;Кофе &amp; круассан в «Сити»&quot;." name="description">
        """
        let parsed = CaptionParser.parse(pageHTML: html, embedHTML: nil)
        XCTAssertEqual(parsed.caption, "Кофе & круассан в «Сити»")
        XCTAssertEqual(parsed.author, "anna")
    }

    func testOgTitleFallback() {
        let html = #"<meta property="og:title" content="Ada on Instagram: &quot;hello place&quot;" />"#
        let parsed = CaptionParser.parse(pageHTML: html, embedHTML: nil)
        XCTAssertEqual(parsed.caption, "hello place")
        XCTAssertEqual(parsed.author, "Ada")
        XCTAssertEqual(parsed.captionSource, .ogTitle)
    }

    func testEmbedFallbackAndStripsUsername() {
        let html = """
        <div class="Caption">
          <div class="CaptionUsername"><a href="/u/">user</a></div>
          Первая строка<br>Вторая &amp; третья
        </div>
        """
        let parsed = CaptionParser.parse(pageHTML: "<html></html>", embedHTML: html)
        XCTAssertEqual(parsed.caption, "Первая строка\nВторая & третья")
        XCTAssertEqual(parsed.captionSource, .embed)
        XCTAssertFalse(parsed.caption?.contains("user") ?? true)
    }

    func testLongerEmbedWinsOverShortMeta() {
        let page = #"<meta name="description" content="1 like, 0 comments - a on May 1, 2024: &quot;hi&quot;." />"#
        let embed = #"<div class="Caption">hi there, full caption from the embed</div>"#
        let parsed = CaptionParser.parse(pageHTML: page, embedHTML: embed)
        XCTAssertEqual(parsed.caption, "hi there, full caption from the embed")
        XCTAssertEqual(parsed.captionSource, .embed)
    }

    func testUnavailablePageIgnoresEmbed() {
        let page = "<html>Sorry, this page isn't available. The link to this photo or video may be broken.</html>"
        let embed = #"<div class="Caption">should not be used</div>"#
        let parsed = CaptionParser.parse(pageHTML: page, embedHTML: embed)
        XCTAssertTrue(parsed.isUnavailable)
        XCTAssertNil(parsed.caption)
    }

    func testJSONCaptionFallback() {
        let html = #"""
        <script>{"edge_media_to_caption":{"edges":[{"node":{"text":"Line one\n📍 Place"}}]}}</script>
        """#
        let parsed = CaptionParser.parse(pageHTML: html, embedHTML: nil)
        XCTAssertEqual(parsed.caption, "Line one\n📍 Place")
        XCTAssertEqual(parsed.captionSource, .mediaJSON)
    }

    func testFixtureFileLoads() throws {
        let html = try TestResources.string(name: "meta_description", ext: "html")
        let parsed = CaptionParser.parse(pageHTML: html, embedHTML: nil)
        XCTAssertEqual(parsed.caption, "📍 Кафе Mandabatmaz")
        XCTAssertEqual(parsed.imageURL, "https://example.com/cover.jpg")
    }

    func testExtractsLinksAndStripsTracking() {
        let text = """
        look https://www.instagram.com/reel/ABC_def-123/?igsh=xyz
        and https://instagram.com/some.user/reels/AbC123/
        https://www.instagram.com/p/AAAA/?igsh=1&img_index=2
        tv https://www.instagram.com/tv/ZZZZ/
        ignore https://www.instagram.com/stories/user/123
        """
        let links = InstagramLinks.extract(from: text)
        XCTAssertEqual(links.map(\.shortcode), ["ABC_def-123", "AbC123", "AAAA", "ZZZZ"])
        XCTAssertEqual(links.map(\.kind), [.reel, .reels, .post, .tv])
        XCTAssertEqual(links[0].canonicalURL, "https://www.instagram.com/reel/ABC_def-123/")
        XCTAssertEqual(links[2].canonicalURL, "https://www.instagram.com/p/AAAA/")
        XCTAssertFalse(links[0].canonicalURL.contains("igsh"))
    }

    func testDuplicateShortcodeKeptOnce() {
        let text = "https://www.instagram.com/p/Same1/ https://www.instagram.com/reel/Same1/?igsh=1"
        let links = InstagramLinks.extract(from: text)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].kind, .post)
    }
}
