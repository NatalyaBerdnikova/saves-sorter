import SwiftUI

struct CollectionView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var controller: AppController

    var body: some View {
        let groups = LibraryGrouping.countries(from: store.library.entries)
        let homeless = LibraryGrouping.withoutCity(store.library.entries)
        List {
            if AppLexicon.value == nil {
                Text(S.lexiconMissing)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if controller.isProcessing {
                Text(S.processing).font(.footnote)
            } else if store.library.posts.contains(where: { $0.status == .pending }) {
                Text(S.pending(store.library.posts.filter { $0.status == .pending }.count))
                    .font(.footnote)
            }
            if !homeless.isEmpty {
                NavigationLink(value: CollectionRoute.withoutCity) {
                    HStack {
                        Label(S.withoutCity, systemImage: "questionmark.circle")
                        Spacer()
                        Text("\(homeless.count)").foregroundStyle(.secondary)
                    }
                }
            }
            if groups.isEmpty && homeless.isEmpty && !controller.isProcessing {
                VStack(alignment: .leading, spacing: 8) {
                    Text(S.emptyTitle).font(.headline)
                    Text(S.emptyBody).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            ForEach(groups, id: \.country) { group in
                let visits = group.cities.reduce(0) { $0 + $1.visits.count }
                let buys = group.cities.reduce(0) { $0 + $1.buys.count }
                if group.cities.count == 1, group.cities[0].city == group.country {
                    NavigationLink(value: CollectionRoute.city(country: group.country, city: group.cities[0].city)) {
                        countryLabel(group.country, cities: 1, visits: visits, buys: buys)
                    }
                } else {
                    NavigationLink(value: CollectionRoute.country(group.country)) {
                        countryLabel(group.country, cities: group.cities.count, visits: visits, buys: buys)
                    }
                }
            }
        }
        .navigationTitle(S.collection)
        .navigationDestination(for: CollectionRoute.self) { route in
            switch route {
            case .country(let country):
                CountryView(country: country)
            case .city(let country, let city):
                CityDetailView(country: country, city: city)
            case .withoutCity:
                WithoutCityView()
            case .search:
                SearchView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: CollectionRoute.search) {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel(S.searchPrompt)
            }
        }
        .refreshable { await controller.refreshAndProcess() }
    }

    private func countryLabel(_ name: String, cities: Int, visits: Int, buys: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.body)
            Text(S.countrySubtitle(cities: cities, visits: visits, buys: buys))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct CountryView: View {
    var country: String
    @EnvironmentObject private var store: LibraryStore
    @State private var share: SharePayload?

    var body: some View {
        let group = LibraryGrouping.countries(from: store.library.entries).first { $0.country == country }
        List {
            ForEach(group?.cities ?? [], id: \.city) { city in
                NavigationLink(value: CollectionRoute.city(country: country, city: city.city)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(city.city)
                        Text(S.citySubtitle(visits: city.visits.count, buys: city.buys.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(country)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(S.exportCountry) { exportVisits() }
            }
        }
        .sheet(item: $share) { ActivitySheet(items: $0.items) }
    }

    private func exportVisits() {
        let entries = LibraryGrouping.confirmed(store.library.entries).filter { $0.country == country && $0.kind == .visit }
        guard let url = ShareFiles.csv(entries: entries, store: store, filename: "SavesSorter-\(country)-visit") else { return }
        share = SharePayload(items: [url])
    }
}

struct CityDetailView: View {
    var country: String
    var city: String
    @EnvironmentObject private var store: LibraryStore
    @State private var kind: EntryKind = .visit
    @State private var editor: EditorRoute?
    @State private var pendingManualPost: SavedPost?
    @State private var share: SharePayload?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            Picker(S.kind, selection: $kind) {
                Text(S.visit).tag(EntryKind.visit)
                Text(S.buy).tag(EntryKind.buy)
            }
            .pickerStyle(.segmented)
            .padding()
            List {
                let rows = currentEntries
                if rows.isEmpty {
                    Text(kind == .visit ? S.emptyVisit : S.emptyBuy)
                        .foregroundStyle(.secondary)
                }
                ForEach(rows) { entry in
                    EntryActions(entry: entry, onEdit: { edit(entry) }, onDelete: {
                        LibraryEdits.deleteEntry(entry.id, in: store)
                    })
                    .swipeActions {
                        Button(S.delete, role: .destructive) {
                            LibraryEdits.deleteEntry(entry.id, in: store)
                        }
                    }
                }
            }
        }
        .navigationTitle(city)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(S.copyNames) { copyNames() }
                    Button(S.exportCSV) { exportCurrent() }
                    Button(S.add) { addEntry() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(S.more)
            }
        }
        .sheet(item: $editor) { route in
            EntryEditor(route: route) { updated in
                if let pendingManualPost, pendingManualPost.id == updated.postId {
                    store.mutate { library in
                        if !library.posts.contains(where: { $0.id == pendingManualPost.id }) {
                            library.posts.append(pendingManualPost)
                        }
                    }
                }
                LibraryEdits.upsert(updated, in: store)
                pendingManualPost = nil
            }
        }
        .sheet(item: $share) { ActivitySheet(items: $0.items) }
        .alert(S.copied, isPresented: $copied) {
            Button(S.close, role: .cancel) {}
        }
    }

    private var currentEntries: [LibraryEntry] {
        LibraryGrouping.confirmed(store.library.entries).filter {
            $0.country == country && $0.city == city && $0.kind == kind
        }
    }

    private func edit(_ entry: LibraryEntry) {
        let caption = store.library.posts.first { $0.id == entry.postId }?.caption
        editor = EditorRoute(entry: entry, caption: caption)
    }

    private func addEntry() {
        let post = SavedPost(
            instagramURL: "",
            shortcode: "manual-\(UUID().uuidString.prefix(8))",
            mediaKind: .post,
            status: .sorted
        )
        pendingManualPost = post
        editor = EditorRoute(
            entry: blankEntry(post: post, kind: kind, city: city, country: country),
            caption: nil
        )
    }

    private func copyNames() {
        UIPasteboard.general.string = ExportService.namesList(entries: currentEntries)
        copied = true
    }

    private func exportCurrent() {
        let suffix = kind == .visit ? "visit" : "buy"
        guard let url = ShareFiles.csv(entries: currentEntries, store: store, filename: "SavesSorter-\(city)-\(suffix)") else { return }
        share = SharePayload(items: [url])
    }
}

struct WithoutCityView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var editor: EditorRoute?

    var body: some View {
        let rows = LibraryGrouping.withoutCity(store.library.entries)
        List {
            Section {
                ForEach(rows) { entry in
                    EntryActions(entry: entry, onEdit: {
                        let caption = store.library.posts.first { $0.id == entry.postId }?.caption
                        editor = EditorRoute(entry: entry, caption: caption)
                    }, onDelete: {
                        LibraryEdits.deleteEntry(entry.id, in: store)
                    })
                    .swipeActions {
                        Button(S.delete, role: .destructive) {
                            LibraryEdits.deleteEntry(entry.id, in: store)
                        }
                    }
                }
            } footer: {
                Text(S.withoutFooter)
            }
        }
        .navigationTitle(S.withoutCity)
        .sheet(item: $editor) { route in
            EntryEditor(route: route) { updated in
                LibraryEdits.upsert(updated, in: store)
            }
        }
    }
}
