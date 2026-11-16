import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let label = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let doneButton = UIButton(type: .system)
    private var didFinish = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = NSLocalizedString("share.working", comment: "")
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        spinner.startAnimating()
        doneButton.setTitle(NSLocalizedString("share.done", comment: ""), for: .normal)
        doneButton.addTarget(self, action: #selector(finish), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [spinner, label, doneButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        Task { await ingest() }
    }

    @objc private func finish() {
        guard !didFinish else { return }
        didFinish = true
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func ingest() async {
        let texts = await loadTexts()
        let links = texts.flatMap { InstagramLinks.extract(from: $0) }
        if links.isEmpty {
            await show(NSLocalizedString("share.none", comment: ""), spinning: false)
            return
        }
        let created = IngestService.add(links: links, to: .shared)
        if created.isEmpty {
            await show(NSLocalizedString("share.duplicate", comment: ""), spinning: false)
            return
        }
        await show(NSLocalizedString("share.saved", comment: ""), spinning: true)
        for id in created {
            await IngestService.process(
                postID: id,
                store: .shared,
                settings: .rulesOnly,
                policy: .shareExtension
            )
        }
        await show(NSLocalizedString("share.finished", comment: ""), spinning: false)
        try? await Task.sleep(nanoseconds: 700_000_000)
        await MainActor.run { self.finish() }
    }

    @MainActor
    private func show(_ text: String, spinning: Bool) {
        label.text = text
        if spinning {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }

    private func loadTexts() async -> [String] {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return [] }
        var texts: [String] = []
        for item in items {
            if let text = item.attributedContentText?.string, !text.isEmpty {
                texts.append(text)
            }
            for provider in item.attachments ?? [] {
                if let value = await load(provider) {
                    texts.append(value)
                }
            }
        }
        return texts
    }

    private func load(_ provider: NSItemProvider) async -> String? {
        let types = [UTType.url.identifier, UTType.plainText.identifier, UTType.text.identifier]
        for type in types where provider.hasItemConformingToTypeIdentifier(type) {
            do {
                let item = try await provider.loadItem(forTypeIdentifier: type)
                if let url = item as? URL { return url.absoluteString }
                if let text = item as? String { return text }
                if let data = item as? Data { return String(data: data, encoding: .utf8) }
            } catch {
                continue
            }
        }
        return nil
    }
}
