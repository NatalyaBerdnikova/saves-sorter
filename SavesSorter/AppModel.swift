import Combine
import Foundation

enum AppLexicon {
    static let value: GeoLexicon? = try? GeoLexicon.loadBundled()
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var aiEnabled: Bool {
        didSet { persist() }
    }
    @Published var provider: AIProvider {
        didSet { persist() }
    }
    @Published var openAIModel: String {
        didSet { persist() }
    }
    @Published var anthropicModel: String {
        didSet { persist() }
    }

    private let defaults = AppDefaults.suite
    private var ready = false

    init() {
        aiEnabled = defaults.bool(forKey: "ai.enabled")
        if let raw = defaults.string(forKey: "ai.provider"), let stored = AIProvider(rawValue: raw) {
            provider = stored
        } else {
            provider = .openAI
        }
        openAIModel = defaults.string(forKey: "ai.model.openai") ?? AIProvider.openAI.defaultModel
        anthropicModel = defaults.string(forKey: "ai.model.anthropic") ?? AIProvider.anthropic.defaultModel
        ready = true
    }

    func persist() {
        guard ready else { return }
        defaults.set(aiEnabled, forKey: "ai.enabled")
        defaults.set(provider.rawValue, forKey: "ai.provider")
        defaults.set(openAIModel, forKey: "ai.model.openai")
        defaults.set(anthropicModel, forKey: "ai.model.anthropic")
    }

    func makeProcessingSettings() -> ProcessingSettings {
        let model = provider == .openAI ? openAIModel : anthropicModel
        return ProcessingSettings(
            allowAI: aiEnabled,
            provider: provider,
            apiKey: KeychainStore.get(provider.keychainAccount),
            model: model
        )
    }

    var hasKeyForProvider: Bool {
        guard let key = KeychainStore.get(provider.keychainAccount) else { return false }
        return !key.isEmpty
    }

    var activeModel: String {
        get { provider == .openAI ? openAIModel : anthropicModel }
        set {
            if provider == .openAI {
                openAIModel = newValue
            } else {
                anthropicModel = newValue
            }
        }
    }
}

@MainActor
final class AppController: ObservableObject {
    let store = LibraryStore.shared
    let settings = AppSettings()
    @Published var isProcessing = false
    private var running = false

    func refreshAndProcess() async {
        store.reload()
        await processPending()
    }

    func processPending() async {
        guard !running else { return }
        running = true
        isProcessing = true
        defer {
            running = false
            isProcessing = false
        }
        let ids = store.snapshot().posts.filter { $0.status == .pending }.map(\.id)
        for id in ids {
            if Task.isCancelled { return }
            await IngestService.process(
                postID: id,
                store: store,
                settings: settings.makeProcessingSettings(),
                policy: .app
            )
        }
    }

    func retry(postID: UUID) async {
        store.mutate { library in
            guard let index = library.posts.firstIndex(where: { $0.id == postID }) else { return }
            library.posts[index].status = .pending
            library.posts[index].failureCode = nil
            library.posts[index].failureDetail = nil
            library.posts[index].updatedAt = Date()
        }
        await IngestService.process(
            postID: postID,
            store: store,
            settings: settings.makeProcessingSettings(),
            policy: .app
        )
    }
}
