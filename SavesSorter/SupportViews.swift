import SwiftUI
import UIKit

enum CollectionRoute: Hashable {
    case country(String)
    case city(country: String, city: String)
    case withoutCity
    case search
}

struct EditorRoute: Identifiable {
    let id = UUID()
    var entry: LibraryEntry
    var caption: String?
}

struct SharePayload: Identifiable {
    let id = UUID()
    var items: [Any]
}

struct ActivitySheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            let window = scene?.keyWindow ?? scene?.windows.first
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window?.bounds.midX ?? 0, y: window?.bounds.midY ?? 0, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ThumbView: View {
    var filename: String?
    var directory: URL

    var body: some View {
        Group {
            if let filename,
               let data = ThumbnailCache.load(named: filename, directory: directory),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.12))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct EntryActions: View {
    var entry: LibraryEntry
    var onEdit: () -> Void
    var onDelete: () -> Void
    @State private var copied = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.body)
            if let shop = entry.shop?.nilIfBlank, shop.caseInsensitiveCompare(entry.title) != .orderedSame {
                Text(S.shopLine(shop))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if entry.needsReview {
                Text(S.reviewTag)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 16) {
                Button(S.copyName) { copy(entry.title) }
                if let url = URL(string: entry.instagramURL) {
                    Button(S.openPost) { openURL(url) }
                }
                if let maps = MapsLink.url(for: entry) {
                    Button(S.openMaps) { openURL(maps) }
                }
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .alert(S.copied, isPresented: $copied) {
            Button(S.close, role: .cancel) {}
        }
        .contextMenu {
            Button(S.edit, action: onEdit)
            Button(S.delete, role: .destructive, action: onDelete)
        }
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        copied = true
    }
}

enum ShareFiles {
    static func csv(entries: [LibraryEntry], store: LibraryStore, filename: String) -> URL? {
        let text = ExportService.csv(entries: entries) { entry in
            if let note = entry.note?.nilIfBlank { return note }
            let caption = store.snapshot().posts.first { $0.id == entry.postId }?.caption ?? ""
            return String(caption.prefix(180))
        }
        return write(Data(text.utf8), filename: filename, ext: "csv")
    }

    static func json(_ library: Library) -> URL? {
        guard let data = try? LibraryCoding.encode(library) else { return nil }
        return write(data, filename: "SavesSorter-backup", ext: "json")
    }

    static func safe(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(scalars).replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "list" : trimmed
    }

    private static func write(_ data: Data, filename: String, ext: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe(filename)).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

func blankEntry(post: SavedPost, kind: EntryKind, city: String? = nil, country: String? = nil) -> LibraryEntry {
    LibraryEntry(
        postId: post.id,
        kind: kind,
        title: "",
        city: city,
        country: country,
        instagramURL: post.instagramURL,
        needsReview: true,
        confidence: 1
    )
}
