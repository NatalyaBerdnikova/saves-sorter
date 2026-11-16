import Foundation

enum ThumbnailCache {
    static func save(_ data: Data, id: UUID, directory: URL) throws -> String {
        let folder = directory.appendingPathComponent("Thumbs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(id.uuidString).img"
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        return name
    }

    static func load(named name: String, directory: URL) -> Data? {
        let url = directory.appendingPathComponent("Thumbs", isDirectory: true).appendingPathComponent(name)
        return try? Data(contentsOf: url)
    }

    static func delete(named name: String?, directory: URL) {
        guard let name else { return }
        let url = directory.appendingPathComponent("Thumbs", isDirectory: true).appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
    }
}
