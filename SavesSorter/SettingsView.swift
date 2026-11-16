import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var controller: AppController
    @State private var keyDraft = ""
    @State private var share: SharePayload?
    @State private var importing = false
    @State private var pendingImport: Library?
    @State private var importFailed = false
    @State private var hasKey = false

    var body: some View {
        Form {
            Section {
                Toggle(S.aiToggle, isOn: $settings.aiEnabled)
                Picker(S.provider, selection: $settings.provider) {
                    Text(S.openAI).tag(AIProvider.openAI)
                    Text(S.anthropic).tag(AIProvider.anthropic)
                }
                TextField(S.model, text: modelBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(S.apiKey, text: $keyDraft)
                Button(S.saveKey) { saveKey() }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if hasKey {
                    Text(S.keySaved).font(.footnote).foregroundStyle(.secondary)
                    Button(S.deleteKey, role: .destructive) { deleteKey() }
                } else {
                    Text(S.keyMissing).font(.footnote).foregroundStyle(.secondary)
                }
                if let error = AILog.last {
                    Text(S.aiError(error)).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text(S.aiSection)
            } footer: {
                Text(S.aiNote)
            }

            Section(S.dataSection) {
                Button(S.exportJSON) { exportJSON() }
                Button(S.importJSON) { importing = true }
                Button(S.exportVisits) { export(kind: .visit) }
                Button(S.exportBuys) { export(kind: .buy) }
            }

            Section(S.help) {
                Text(S.helpBody).font(.footnote)
            }
            Section(S.limits) {
                Text(S.limitsBody).font(.footnote)
            }

            Section(S.diag) {
                Text(S.bundle(AppIdentity.bundleIdentifier)).font(.footnote)
                Text(S.group(AppIdentity.appGroupID)).font(.footnote)
                Text(S.pendingCount(store.library.posts.filter { $0.status == .pending }.count))
                    .font(.footnote)
                if store.usingFallbackStorage {
                    Text(S.fallback).font(.footnote).foregroundStyle(.red)
                }
                if let warning = store.storageWarning {
                    Text(warning).font(.footnote).foregroundStyle(.red)
                }
                Button(S.processNow) { Task { await controller.processPending() } }
                    .disabled(controller.isProcessing)
            }
        }
        .navigationTitle(S.settings)
        .onAppear { hasKey = settings.hasKeyForProvider }
        .onChange(of: settings.provider) { _, _ in
            hasKey = settings.hasKeyForProvider
            keyDraft = ""
        }
        .sheet(item: $share) { ActivitySheet(items: $0.items) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importFile(url)
            case .failure:
                importFailed = true
            }
        }
        .confirmationDialog(S.importChoice, isPresented: importPresented, titleVisibility: .visible) {
            Button(S.replace) {
                if let pendingImport { store.replaceAll(pendingImport) }
                pendingImport = nil
            }
            Button(S.merge) {
                if let pendingImport {
                    store.replaceAll(LibraryMerge.merge(base: store.snapshot(), incoming: pendingImport))
                }
                pendingImport = nil
            }
            Button(S.cancel, role: .cancel) { pendingImport = nil }
        }
        .alert(S.importFailed, isPresented: $importFailed) {
            Button(S.close, role: .cancel) {}
        }
    }

    private var modelBinding: Binding<String> {
        Binding(get: { settings.activeModel }, set: { settings.activeModel = $0 })
    }

    private var importPresented: Binding<Bool> {
        Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })
    }

    private func saveKey() {
        let secret = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { return }
        try? KeychainStore.set(secret, account: settings.provider.keychainAccount)
        keyDraft = ""
        hasKey = settings.hasKeyForProvider
        AILog.clear()
    }

    private func deleteKey() {
        KeychainStore.delete(settings.provider.keychainAccount)
        hasKey = false
    }

    private func exportJSON() {
        guard let url = ShareFiles.json(store.snapshot()) else { return }
        share = SharePayload(items: [url])
    }

    private func export(kind: EntryKind) {
        let entries = LibraryGrouping.confirmed(store.library.entries).filter { $0.kind == kind }
        let name = kind == .visit ? "SavesSorter-visits" : "SavesSorter-buys"
        guard let url = ShareFiles.csv(entries: entries, store: store, filename: name) else { return }
        share = SharePayload(items: [url])
    }

    private func importFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let library = try? LibraryCoding.decode(data),
              library.schemaVersion <= 1 else {
            importFailed = true
            return
        }
        pendingImport = library
    }
}
