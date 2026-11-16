import Combine
import Foundation

final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var library = Library()
    @Published private(set) var usingFallbackStorage = false
    @Published private(set) var storageWarning: String?

    let storageDirectory: URL
    private let fileURL: URL
    private let queue = DispatchQueue(label: "savessorter.library")
    private let coordinator = NSFileCoordinator(filePresenter: nil)
    private var memory = Library()

    init(directory: URL? = nil) {
        let resolved = Self.resolveDirectory(override: directory)
        storageDirectory = resolved.url
        usingFallbackStorage = resolved.fallback
        fileURL = resolved.url.appendingPathComponent("library.json")
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        switch Self.read(from: fileURL) {
        case .loaded(let loaded):
            memory = loaded
        case .missing:
            memory = Library()
            try? Self.write(memory, to: fileURL)
        case .corrupt:
            memory = Library()
            try? FileManager.default.removeItem(at: fileURL)
            try? Self.write(memory, to: fileURL)
            storageWarning = "Файл коллекции был повреждён. Копия лежит рядом: library.corrupt.json"
        }
        library = memory
    }

    func reload() {
        queue.sync {
            switch Self.read(from: fileURL) {
            case .loaded(let loaded):
                memory = loaded
            case .missing:
                memory = Library()
            case .corrupt:
                DispatchQueue.main.async {
                    self.storageWarning = "Файл коллекции повреждён. Текущие данные в памяти не затёрты."
                }
            }
            let snapshot = memory
            DispatchQueue.main.async { self.library = snapshot }
        }
    }

    func snapshot() -> Library {
        queue.sync { memory }
    }

    func mutate(_ body: (inout Library) -> Void) {
        queue.sync {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try? Self.write(Library(), to: fileURL)
            }
            var coordinationError: NSError?
            var updated = memory
            var warning: String?
            coordinator.coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordinationError) { url in
                let base: Library
                switch Self.read(from: url) {
                case .corrupt:
                    try? FileManager.default.removeItem(at: url)
                    base = memory
                    warning = "Повреждённый файл сохранён как library.corrupt.json. Коллекция продолжена из памяти."
                case .missing:
                    base = Library()
                case .loaded(let library):
                    base = library
                }
                var library = base
                body(&library)
                library.schemaVersion = max(library.schemaVersion, 1)
                do {
                    try Self.write(library, to: url)
                    updated = library
                } catch {
                    warning = error.localizedDescription
                }
            }
            if let coordinationError, warning == nil {
                warning = coordinationError.localizedDescription
            }
            memory = updated
            DispatchQueue.main.async {
                self.library = updated
                if let warning { self.storageWarning = warning }
            }
        }
    }

    func replaceAll(_ library: Library) {
        mutate { current in
            current = library
        }
    }

    private static func resolveDirectory(override: URL?) -> (url: URL, fallback: Bool) {
        if let override { return (override, false) }
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentity.appGroupID) {
            return (container.appendingPathComponent("Library", isDirectory: true), false)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return (base.appendingPathComponent("SavesSorter", isDirectory: true), true)
    }

    private enum ReadResult {
        case missing
        case loaded(Library)
        case corrupt
    }

    private static func read(from url: URL) -> ReadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .corrupt }
        if data.isEmpty { return .missing }
        guard let library = try? LibraryCoding.decode(data) else {
            let backup = url.deletingLastPathComponent().appendingPathComponent("library.corrupt.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
            return .corrupt
        }
        return .loaded(library)
    }

    private static func write(_ library: Library, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try LibraryCoding.encode(library)
        let temporary = directory.appendingPathComponent("library.json.tmp")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }
}
