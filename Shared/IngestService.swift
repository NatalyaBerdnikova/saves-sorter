import Foundation

struct ProcessingSettings {
    var allowAI: Bool
    var provider: AIProvider
    var apiKey: String?
    var model: String

    static let rulesOnly = ProcessingSettings(allowAI: false, provider: .openAI, apiKey: nil, model: "")
}

enum IngestService {
    @discardableResult
    static func add(links: [InstagramLink], to store: LibraryStore) -> [UUID] {
        var created: [UUID] = []
        store.mutate { library in
            for link in links {
                if let index = library.posts.firstIndex(where: { $0.shortcode == link.shortcode }) {
                    if library.posts[index].status == .failed {
                        library.posts[index].status = .pending
                        library.posts[index].failureCode = nil
                        library.posts[index].failureDetail = nil
                        library.posts[index].updatedAt = Date()
                        created.append(library.posts[index].id)
                    }
                    continue
                }
                let post = SavedPost(
                    instagramURL: link.canonicalURL,
                    shortcode: link.shortcode,
                    mediaKind: link.kind
                )
                library.posts.append(post)
                created.append(post.id)
            }
        }
        return created
    }

    static func process(postID: UUID, store: LibraryStore, settings: ProcessingSettings, policy: FetchPolicy) async {
        guard let post = store.snapshot().posts.first(where: { $0.id == postID }) else { return }
        guard post.status == .pending else { return }
        let link = InstagramLink(shortcode: post.shortcode, kind: post.mediaKind, canonicalURL: post.instagramURL)
        let outcome = await InstagramFetcher(policy: policy).fetch(link)
        switch outcome {
        case .success(let caption, let author, let imageURL):
            await apply(
                caption: caption,
                author: author,
                imageURL: imageURL,
                post: post,
                store: store,
                settings: settings,
                policy: policy
            )
        case .unavailable:
            mark(store, postID: post.id, status: .failed, code: .unavailable, detail: nil, caption: post.caption, author: post.author)
        case .blocked:
            mark(store, postID: post.id, status: .failed, code: .blocked, detail: nil, caption: post.caption, author: post.author)
        case .failed(let message):
            mark(store, postID: post.id, status: .failed, code: .network, detail: message, caption: post.caption, author: post.author)
        }
    }

    private static func apply(
        caption: String,
        author: String?,
        imageURL: String?,
        post: SavedPost,
        store: LibraryStore,
        settings: ProcessingSettings,
        policy: FetchPolicy
    ) async {
        let trimmed = caption.cleanedCaption
        guard !trimmed.isEmpty else {
            mark(store, postID: post.id, status: .failed, code: .emptyCaption, detail: nil, caption: caption, author: author)
            return
        }
        guard let lexicon = try? GeoLexicon.loadBundled() else {
            mark(store, postID: post.id, status: .failed, code: .nothingUseful, detail: "GeoData.json", caption: trimmed, author: author)
            return
        }

        var result = RuleClassifier(lexicon: lexicon).classify(trimmed)
        if settings.allowAI, let apiKey = settings.apiKey, !apiKey.isEmpty {
            do {
                let payload = try await AIClient.classify(
                    caption: trimmed,
                    provider: settings.provider,
                    apiKey: apiKey,
                    model: settings.model.isEmpty ? settings.provider.defaultModel : settings.model
                )
                AILog.clear()
                let drafts = AIResponseParser.drafts(
                    from: payload,
                    lexicon: lexicon,
                    fallbackCities: lexicon.uniqueCities(in: trimmed)
                )
                if drafts.isEmpty {
                    result.entries = result.entries.map { entry in
                        var copy = entry
                        copy.needsReview = true
                        return copy
                    }
                } else {
                    result = ClassificationResult(entries: drafts, nothingUseful: false, nothingReason: nil)
                }
            } catch {
                AILog.record(aiMessage(error))
            }
        }

        if result.entries.isEmpty {
            let code: FailureCode = result.nothingReason == .placesInVideo ? .placesInVideo : .nothingUseful
            mark(store, postID: post.id, status: .failed, code: code, detail: nil, caption: trimmed, author: author)
            await cacheThumbnail(imageURL, postID: post.id, store: store, policy: policy)
            return
        }

        let drafts = result.entries
        store.mutate { library in
            guard let index = library.posts.firstIndex(where: { $0.id == post.id }) else { return }
            library.entries.removeAll { $0.postId == post.id }
            for draft in drafts {
                library.entries.append(
                    LibraryEntry(
                        postId: post.id,
                        kind: draft.kind,
                        title: draft.title,
                        shop: draft.shop,
                        city: draft.city,
                        country: draft.country,
                        instagramURL: post.instagramURL,
                        needsReview: draft.needsReview,
                        confidence: draft.confidence
                    )
                )
            }
            library.posts[index].caption = trimmed
            library.posts[index].author = author ?? library.posts[index].author
            library.posts[index].failureCode = nil
            library.posts[index].failureDetail = nil
            library.posts[index].updatedAt = Date()
            let related = library.entries.filter { $0.postId == post.id }
            library.posts[index].status = related.allSatisfy { !$0.needsReview } ? .sorted : .needsReview
        }
        await cacheThumbnail(imageURL, postID: post.id, store: store, policy: policy)
    }

    private static func mark(
        _ store: LibraryStore,
        postID: UUID,
        status: PostStatus,
        code: FailureCode?,
        detail: String?,
        caption: String?,
        author: String?
    ) {
        store.mutate { library in
            guard let index = library.posts.firstIndex(where: { $0.id == postID }) else { return }
            let related = library.entries.filter { $0.postId == postID }
            library.posts[index].updatedAt = Date()
            if let caption { library.posts[index].caption = caption }
            if let author { library.posts[index].author = author }
            if related.isEmpty {
                library.posts[index].status = status
                library.posts[index].failureCode = code
                library.posts[index].failureDetail = detail
            } else {
                library.posts[index].failureCode = code
                library.posts[index].failureDetail = detail
                library.posts[index].status = related.allSatisfy { !$0.needsReview } ? .sorted : .needsReview
            }
        }
    }

    private static func cacheThumbnail(_ imageURL: String?, postID: UUID, store: LibraryStore, policy: FetchPolicy) async {
        guard let imageURL, let url = URL(string: imageURL) else { return }
        guard let data = await InstagramFetcher(policy: policy).downloadImage(url) else { return }
        guard let name = try? ThumbnailCache.save(data, id: postID, directory: store.storageDirectory) else { return }
        store.mutate { library in
            guard let index = library.posts.firstIndex(where: { $0.id == postID }) else { return }
            if let previous = library.posts[index].thumbnailFile, previous != name {
                ThumbnailCache.delete(named: previous, directory: store.storageDirectory)
            }
            library.posts[index].thumbnailFile = name
        }
    }

    private static func aiMessage(_ error: Error) -> String {
        if let ai = error as? AIClientError {
            switch ai {
            case .rejected: return "Ключ отклонён"
            case .empty: return "Модель вернула пустой ответ"
            case .badResponse(let message): return message
            }
        }
        return error.localizedDescription
    }
}

enum LibraryEdits {
    static func upsert(_ entry: LibraryEntry, in store: LibraryStore) {
        store.mutate { library in
            if let index = library.entries.firstIndex(where: { $0.id == entry.id }) {
                library.entries[index] = entry
            } else {
                library.entries.append(entry)
            }
            refreshPost(entry.postId, in: &library)
        }
    }

    static func deleteEntry(_ id: UUID, in store: LibraryStore) {
        store.mutate { library in
            guard let entry = library.entries.first(where: { $0.id == id }) else { return }
            library.entries.removeAll { $0.id == id }
            refreshPost(entry.postId, in: &library)
        }
    }

    static func deletePost(_ id: UUID, in store: LibraryStore) {
        let thumb = store.snapshot().posts.first { $0.id == id }?.thumbnailFile
        store.mutate { library in
            library.posts.removeAll { $0.id == id }
            library.entries.removeAll { $0.postId == id }
        }
        ThumbnailCache.delete(named: thumb, directory: store.storageDirectory)
    }

    static func normalized(_ entry: LibraryEntry, lexicon: GeoLexicon?) -> LibraryEntry {
        guard let lexicon else { return entry }
        var copy = entry
        let city = lexicon.normalize(city: copy.city, country: copy.country)
        copy.city = city.city
        copy.country = city.country
        copy.title = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.shop = copy.shop?.nilIfBlank
        if (copy.city ?? "").isEmpty || (copy.country ?? "").isEmpty {
            copy.needsReview = true
        }
        return copy
    }

    private static func refreshPost(_ postID: UUID, in library: inout Library) {
        guard let index = library.posts.firstIndex(where: { $0.id == postID }) else { return }
        library.posts[index].updatedAt = Date()
        let related = library.entries.filter { $0.postId == postID }
        if related.isEmpty {
            if library.posts[index].instagramURL.isEmpty {
                library.posts.remove(at: index)
                return
            }
            if library.posts[index].status != .pending {
                library.posts[index].status = .failed
                if library.posts[index].failureCode == nil {
                    library.posts[index].failureCode = .nothingUseful
                }
            }
            return
        }
        library.posts[index].failureCode = nil
        library.posts[index].failureDetail = nil
        library.posts[index].status = related.allSatisfy { !$0.needsReview } ? .sorted : .needsReview
    }
}
