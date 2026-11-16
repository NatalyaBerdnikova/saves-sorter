import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var editor: EditorRoute?

    var body: some View {
        let rows = store.library.entries.filter(\.needsReview)
        List {
            if rows.isEmpty {
                Text(S.reviewEmpty).foregroundStyle(.secondary)
            }
            ForEach(rows) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        ThumbView(
                            filename: store.library.posts.first { $0.id == entry.postId }?.thumbnailFile,
                            directory: store.storageDirectory
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.kind == .visit ? S.visit : S.buy)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.title.isEmpty ? S.namePlaceholder : entry.title)
                                .font(.body)
                            Text([entry.city, entry.country].compactMap { $0?.nilIfBlank }.joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if (entry.city ?? "").isEmpty {
                                Text(S.needsCity)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    if let caption = store.library.posts.first(where: { $0.id == entry.postId })?.caption?.nilIfBlank {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                    HStack {
                        Button(S.confirm) { confirm(entry) }
                            .disabled((entry.city ?? "").isEmpty || (entry.country ?? "").isEmpty || entry.title.nilIfBlank == nil)
                        Button(S.fix) { open(entry) }
                    }
                    .buttonStyle(.borderless)
                }
                .swipeActions {
                    Button(S.delete, role: .destructive) {
                        LibraryEdits.deleteEntry(entry.id, in: store)
                    }
                }
            }
        }
        .navigationTitle(S.review)
        .sheet(item: $editor) { route in
            EntryEditor(route: route) { updated in
                LibraryEdits.upsert(updated, in: store)
            }
        }
    }

    private func confirm(_ entry: LibraryEntry) {
        var copy = LibraryEdits.normalized(entry, lexicon: AppLexicon.value)
        guard copy.title.nilIfBlank != nil, copy.city?.nilIfBlank != nil, copy.country?.nilIfBlank != nil else {
            open(copy)
            return
        }
        copy.needsReview = false
        LibraryEdits.upsert(copy, in: store)
    }

    private func open(_ entry: LibraryEntry) {
        let caption = store.library.posts.first { $0.id == entry.postId }?.caption
        editor = EditorRoute(entry: entry, caption: caption)
    }
}

struct UnparsedView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var controller: AppController
    @State private var editor: EditorRoute?
    @Environment(\.openURL) private var openURL

    var body: some View {
        let posts = store.library.posts.filter { $0.status == .failed }
        List {
            if posts.isEmpty {
                Text(S.unparsedEmpty).foregroundStyle(.secondary)
            }
            ForEach(posts) { post in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        ThumbView(filename: post.thumbnailFile, directory: store.storageDirectory)
                        VStack(alignment: .leading, spacing: 4) {
                            if let url = URL(string: post.instagramURL) {
                                Button(post.instagramURL) { openURL(url) }
                                    .font(.subheadline)
                                    .lineLimit(2)
                            } else {
                                Text(post.instagramURL).font(.subheadline)
                            }
                            Text(S.failure(post.failureCode))
                            if let detail = post.failureDetail?.nilIfBlank {
                                Text(S.failureDetail(detail))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let caption = post.caption?.nilIfBlank {
                                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                    }
                    HStack {
                        Button(S.retry) { Task { await controller.retry(postID: post.id) } }
                        Button(S.manual) { manual(post) }
                        Button(S.delete, role: .destructive) { LibraryEdits.deletePost(post.id, in: store) }
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                }
                .swipeActions {
                    Button(S.delete, role: .destructive) { LibraryEdits.deletePost(post.id, in: store) }
                }
            }
        }
        .navigationTitle(S.unparsed)
        .toolbar {
            if !posts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(S.retryAll) {
                        Task {
                            for post in posts {
                                await controller.retry(postID: post.id)
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $editor) { route in
            EntryEditor(route: route) { updated in
                LibraryEdits.upsert(updated, in: store)
            }
        }
    }

    private func manual(_ post: SavedPost) {
        editor = EditorRoute(entry: blankEntry(post: post, kind: .visit), caption: post.caption)
    }
}

struct SearchView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var query = ""
    @State private var editor: EditorRoute?
    @Environment(\.openURL) private var openURL

    var body: some View {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = needle.isEmpty ? [] : matchingEntries(needle)
        let posts = needle.isEmpty ? [] : matchingPosts(needle)
        List {
            if !needle.isEmpty && entries.isEmpty && posts.isEmpty {
                Text(S.searchEmpty).foregroundStyle(.secondary)
            }
            let visits = entries.filter { $0.kind == .visit }
            let buys = entries.filter { $0.kind == .buy }
            if !visits.isEmpty {
                Section(S.searchVisits) {
                    ForEach(visits) { entry in
                        searchEntry(entry)
                    }
                }
            }
            if !buys.isEmpty {
                Section(S.searchBuys) {
                    ForEach(buys) { entry in
                        searchEntry(entry)
                    }
                }
            }
            if !posts.isEmpty {
                Section(S.searchUnparsed) {
                    ForEach(posts) { post in
                        VStack(alignment: .leading, spacing: 4) {
                            Button(post.instagramURL) {
                                if let url = URL(string: post.instagramURL) { openURL(url) }
                            }
                            Text(S.failure(post.failureCode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(S.searchPrompt)
        .searchable(text: $query, prompt: S.searchPrompt)
        .sheet(item: $editor) { route in
            EntryEditor(route: route) { LibraryEdits.upsert($0, in: store) }
        }
    }

    private func searchEntry(_ entry: LibraryEntry) -> some View {
        Button {
            let caption = store.library.posts.first { $0.id == entry.postId }?.caption
            editor = EditorRoute(entry: entry, caption: caption)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                Text([entry.shop, entry.city, entry.country].compactMap { $0?.nilIfBlank }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.needsReview {
                    Text(S.reviewTag).font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    private func matchingEntries(_ needle: String) -> [LibraryEntry] {
        store.library.entries.filter { entry in
            let caption = store.library.posts.first { $0.id == entry.postId }?.caption ?? ""
            return [entry.title, entry.shop ?? "", entry.city ?? "", entry.country ?? "", entry.note ?? "", caption]
                .contains { $0.localizedStandardContains(needle) }
        }
    }

    private func matchingPosts(_ needle: String) -> [SavedPost] {
        store.library.posts.filter { post in
            guard post.status == .failed else { return false }
            return [post.instagramURL, post.caption ?? "", post.author ?? "", S.failure(post.failureCode)]
                .contains { $0.localizedStandardContains(needle) }
        }
    }
}
