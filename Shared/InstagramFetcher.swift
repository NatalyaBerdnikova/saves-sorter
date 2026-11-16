import Foundation
import os

struct FetchPolicy {
    var timeout: TimeInterval
    var tryAlternatePath: Bool
    var tryEmbed: Bool

    static let app = FetchPolicy(timeout: 20, tryAlternatePath: true, tryEmbed: true)
    static let shareExtension = FetchPolicy(timeout: 6, tryAlternatePath: false, tryEmbed: true)
}

enum FetchOutcome {
    case success(caption: String, author: String?, imageURL: String?)
    case unavailable
    case blocked
    case failed(String)
}

struct InstagramFetcher {
    var policy: FetchPolicy
    static let userAgent = "Shortcuts/2607.0.2 CFNetwork/1568.100.1 Darwin/24.0.0"
    private static let log = Logger(subsystem: "savessorter", category: "fetch")

    func fetch(_ link: InstagramLink) async -> FetchOutcome {
        var urls = [pageURL(link, path: link.kind.primaryPath)]
        if policy.tryAlternatePath {
            let other = link.kind.primaryPath == "reel" ? "p" : "reel"
            urls.append(pageURL(link, path: other))
        }

        var lastError = "Нет ответа"
        var sawBlocked = false
        for (index, url) in urls.enumerated() {
            switch await load(url) {
            case .html(let html, let finalURL):
                if CaptionParser.isUnavailable(html), index == 0 {
                    return .unavailable
                }
                if isLoginWall(html, finalURL: finalURL) {
                    sawBlocked = true
                    continue
                }
                let parsed = CaptionParser.parse(pageHTML: html, embedHTML: nil)
                if let caption = parsed.caption?.nilIfBlank {
                    Self.log.info("caption from page \(link.shortcode, privacy: .public)")
                    return .success(caption: caption, author: parsed.author, imageURL: parsed.imageURL)
                }
            case .unavailable:
                if index == 0 { return .unavailable }
            case .failed(let message):
                lastError = message
            }
        }

        if policy.tryEmbed, let embedURL = URL(string: "https://www.instagram.com/p/\(link.shortcode)/embed/captioned/") {
            if case .html(let html, _) = await load(embedURL) {
                if CaptionParser.isUnavailable(html) { return .unavailable }
                let parsed = CaptionParser.parse(pageHTML: nil, embedHTML: html)
                if let caption = parsed.caption?.nilIfBlank {
                    return .success(caption: caption, author: parsed.author, imageURL: nil)
                }
            }
        }

        if sawBlocked { return .blocked }
        Self.log.error("fetch failed \(link.shortcode, privacy: .public)")
        return .failed(lastError)
    }

    func downloadImage(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: min(policy.timeout, 15))
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            guard data.count <= 2_000_000 else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private func pageURL(_ link: InstagramLink, path: String) -> URL {
        URL(string: "https://www.instagram.com/\(path)/\(link.shortcode)/")!
    }

    private func load(_ url: URL) async -> LoadResult {
        var request = URLRequest(url: url, timeoutInterval: policy.timeout)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("ru,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed("Пустой ответ") }
            if http.statusCode == 404 { return .unavailable }
            if !(200..<300).contains(http.statusCode) { return .failed("HTTP \(http.statusCode)") }
            let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            return .html(html, http.url)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func isLoginWall(_ html: String, finalURL: URL?) -> Bool {
        if finalURL?.absoluteString.contains("/accounts/login") == true { return true }
        return html.contains("/accounts/login") && !html.contains("edge_media_to_caption") && !html.contains("og:title")
    }

    private enum LoadResult {
        case html(String, URL?)
        case unavailable
        case failed(String)
    }
}
