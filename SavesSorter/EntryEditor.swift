import SwiftUI

struct EntryEditor: View {
    @State var entry: LibraryEntry
    var caption: String?
    var onSave: (LibraryEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cityQuery = ""
    @State private var countryQuery = ""

    init(route: EditorRoute, onSave: @escaping (LibraryEntry) -> Void) {
        _entry = State(initialValue: route.entry)
        caption = route.caption
        self.onSave = onSave
        _cityQuery = State(initialValue: route.entry.city ?? "")
        _countryQuery = State(initialValue: route.entry.country ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker(S.kind, selection: $entry.kind) {
                    Text(S.visit).tag(EntryKind.visit)
                    Text(S.buy).tag(EntryKind.buy)
                }
                TextField(S.namePlaceholder, text: $entry.title)
                if entry.kind == .buy {
                    TextField(S.shopPlaceholder, text: shopBinding)
                }
                TextField(S.countryPlaceholder, text: $countryQuery)
                if !countrySuggestions.isEmpty {
                    suggestionList(countrySuggestions.map(\.nameRu)) { name in
                        countryQuery = name
                    }
                }
                TextField(S.cityPlaceholder, text: $cityQuery)
                if !citySuggestions.isEmpty {
                    suggestionList(citySuggestions.map(\.nameRu)) { name in
                        cityQuery = name
                        if let city = AppLexicon.value?.cities.first(where: { $0.nameRu == name }),
                           let country = AppLexicon.value?.country(for: city) {
                            countryQuery = country.nameRu
                        }
                    }
                }
                TextField(S.note, text: noteBinding, axis: .vertical)
                if let caption, !caption.isEmpty {
                    Section(S.caption) {
                        Text(caption).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(S.needsCity).font(.footnote).foregroundStyle(.orange)
                }
            }
            .navigationTitle(entry.title.isEmpty ? S.editorNew : S.editorEdit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(S.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(S.save) { save() }
                        .disabled(entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var shopBinding: Binding<String> {
        Binding(get: { entry.shop ?? "" }, set: { entry.shop = $0 })
    }

    private var noteBinding: Binding<String> {
        Binding(get: { entry.note ?? "" }, set: { entry.note = $0 })
    }

    private var citySuggestions: [City] {
        guard let lexicon = AppLexicon.value else { return [] }
        let query = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        return lexicon.cities.filter { city in
            city.nameRu.localizedStandardContains(query) || city.nameEn.localizedStandardContains(query)
        }.prefix(5).map { $0 }
    }

    private var countrySuggestions: [Country] {
        guard let lexicon = AppLexicon.value else { return [] }
        let query = countryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        return lexicon.countries.filter { country in
            country.nameRu.localizedStandardContains(query) || country.nameEn.localizedStandardContains(query)
        }.prefix(5).map { $0 }
    }

    private func suggestionList(_ titles: [String], pick: @escaping (String) -> Void) -> some View {
        ForEach(titles, id: \.self) { title in
            Button(title) { pick(title) }
        }
    }

    private func save() {
        entry.city = cityQuery.nilIfBlank
        entry.country = countryQuery.nilIfBlank
        entry.shop = entry.shop?.nilIfBlank
        entry.title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var normalized = LibraryEdits.normalized(entry, lexicon: AppLexicon.value)
        let missingPlace = (normalized.city ?? "").isEmpty || (normalized.country ?? "").isEmpty
        normalized.needsReview = missingPlace
        onSave(normalized)
        dismiss()
    }
}
