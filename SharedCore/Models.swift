import Foundation

enum MediaKind: String, Codable, Equatable {
    case post
    case reel
    case reels
    case tv

    var primaryPath: String {
        switch self {
        case .reel, .reels:
            return "reel"
        case .post, .tv:
            return "p"
        }
    }
}

struct InstagramLink: Equatable, Hashable, Codable {
    var shortcode: String
    var kind: MediaKind
    var canonicalURL: String
}

enum EntryKind: String, Codable, Equatable {
    case visit
    case buy
}

enum PostStatus: String, Codable, Equatable {
    case pending
    case failed
    case needsReview
    case sorted
}

enum FailureCode: String, Codable, Equatable {
    case network
    case unavailable
    case emptyCaption
    case nothingUseful
    case placesInVideo
    case blocked
}

enum NothingReason: String, Codable, Equatable {
    case placesInVideo
    case noSignals
}

struct SavedPost: Codable, Equatable, Identifiable {
    var id: UUID
    var instagramURL: String
    var shortcode: String
    var mediaKind: MediaKind
    var status: PostStatus
    var failureCode: FailureCode?
    var failureDetail: String?
    var caption: String?
    var author: String?
    var thumbnailFile: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        instagramURL: String,
        shortcode: String,
        mediaKind: MediaKind,
        status: PostStatus = .pending,
        failureCode: FailureCode? = nil,
        failureDetail: String? = nil,
        caption: String? = nil,
        author: String? = nil,
        thumbnailFile: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.instagramURL = instagramURL
        self.shortcode = shortcode
        self.mediaKind = mediaKind
        self.status = status
        self.failureCode = failureCode
        self.failureDetail = failureDetail
        self.caption = caption
        self.author = author
        self.thumbnailFile = thumbnailFile
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct LibraryEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var postId: UUID
    var kind: EntryKind
    var title: String
    var shop: String?
    var city: String?
    var country: String?
    var note: String?
    var instagramURL: String
    var needsReview: Bool
    var confidence: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        postId: UUID,
        kind: EntryKind,
        title: String,
        shop: String? = nil,
        city: String? = nil,
        country: String? = nil,
        note: String? = nil,
        instagramURL: String,
        needsReview: Bool,
        confidence: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.postId = postId
        self.kind = kind
        self.title = title
        self.shop = shop
        self.city = city
        self.country = country
        self.note = note
        self.instagramURL = instagramURL
        self.needsReview = needsReview
        self.confidence = confidence
        self.createdAt = createdAt
    }
}

struct Library: Codable, Equatable {
    var schemaVersion: Int
    var posts: [SavedPost]
    var entries: [LibraryEntry]

    init(schemaVersion: Int = 1, posts: [SavedPost] = [], entries: [LibraryEntry] = []) {
        self.schemaVersion = schemaVersion
        self.posts = posts
        self.entries = entries
    }
}

struct DraftEntry: Equatable {
    var kind: EntryKind
    var title: String
    var shop: String?
    var city: String?
    var country: String?
    var needsReview: Bool
    var confidence: Double
}

struct ClassificationResult: Equatable {
    var entries: [DraftEntry]
    var nothingUseful: Bool
    var nothingReason: NothingReason?
}

extension DraftEntry: CustomStringConvertible {
    var description: String {
        let whereText = shop ?? "-"
        return "[\(kind.rawValue) \(title) / \(whereText) / \(city ?? "-"), \(country ?? "-") review=\(needsReview) c=\(String(format: "%.2f", confidence))]"
    }
}

extension ClassificationResult: CustomStringConvertible {
    var description: String {
        if entries.isEmpty {
            return "empty \(nothingReason?.rawValue ?? "-")"
        }
        return entries.map(\.description).joined(separator: " | ")
    }
}

enum LibraryCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encode(_ library: Library) throws -> Data {
        try encoder().encode(library)
    }

    static func decode(_ data: Data) throws -> Library {
        try decoder().decode(Library.self, from: data)
    }
}
