import Foundation

enum S {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: args)
    }

    static var collection: String { t("tab.collection") }
    static var review: String { t("tab.review") }
    static var unparsed: String { t("tab.unparsed") }
    static var settings: String { t("tab.settings") }
    static var emptyTitle: String { t("collection.empty.title") }
    static var emptyBody: String { t("collection.empty.body") }
    static var processing: String { t("collection.processing") }
    static var withoutCity: String { t("collection.withoutCity") }
    static var lexiconMissing: String { t("collection.lexiconMissing") }
    static var exportCountry: String { t("country.exportVisits") }
    static var visit: String { t("city.visit") }
    static var buy: String { t("city.buy") }
    static var emptyVisit: String { t("city.empty.visit") }
    static var emptyBuy: String { t("city.empty.buy") }
    static var copyNames: String { t("city.copy") }
    static var exportCSV: String { t("city.export") }
    static var add: String { t("city.add") }
    static var copied: String { t("city.copied") }
    static var openPost: String { t("entry.open") }
    static var openMaps: String { t("entry.maps") }
    static var copyName: String { t("entry.copy") }
    static var delete: String { t("entry.delete") }
    static var edit: String { t("entry.edit") }
    static var deletePost: String { t("entry.deletePost") }
    static var confirm: String { t("review.confirm") }
    static var fix: String { t("review.edit") }
    static var needsCity: String { t("review.needsCity") }
    static var reviewTag: String { t("review.tag") }
    static var reviewEmpty: String { t("review.empty") }
    static var unparsedEmpty: String { t("unparsed.empty") }
    static var retry: String { t("unparsed.retry") }
    static var retryAll: String { t("unparsed.retryAll") }
    static var manual: String { t("unparsed.manual") }
    static var openLink: String { t("unparsed.open") }
    static var searchPrompt: String { t("search.prompt") }
    static var searchEmpty: String { t("search.empty") }
    static var searchVisits: String { t("search.visits") }
    static var searchBuys: String { t("search.buys") }
    static var searchUnparsed: String { t("search.unparsed") }
    static var aiSection: String { t("settings.ai") }
    static var aiToggle: String { t("settings.ai.toggle") }
    static var aiNote: String { t("settings.ai.note") }
    static var provider: String { t("settings.ai.provider") }
    static var openAI: String { t("settings.ai.openai") }
    static var anthropic: String { t("settings.ai.anthropic") }
    static var model: String { t("settings.ai.model") }
    static var apiKey: String { t("settings.ai.key") }
    static var saveKey: String { t("settings.ai.save") }
    static var deleteKey: String { t("settings.ai.delete") }
    static var keySaved: String { t("settings.ai.saved") }
    static var keyMissing: String { t("settings.ai.missing") }
    static var dataSection: String { t("settings.data") }
    static var exportJSON: String { t("settings.exportJSON") }
    static var importJSON: String { t("settings.importJSON") }
    static var exportVisits: String { t("settings.exportVisits") }
    static var exportBuys: String { t("settings.exportBuys") }
    static var importChoice: String { t("settings.importChoice") }
    static var replace: String { t("settings.replace") }
    static var merge: String { t("settings.merge") }
    static var importFailed: String { t("settings.importFailed") }
    static var help: String { t("settings.help") }
    static var helpBody: String { t("settings.help.body") }
    static var limits: String { t("settings.limits") }
    static var limitsBody: String { t("settings.limits.body") }
    static var diag: String { t("settings.diag") }
    static var fallback: String { t("settings.fallback") }
    static var processNow: String { t("settings.process") }
    static var more: String { t("common.more") }
    static var cancel: String { t("common.cancel") }
    static var close: String { t("common.close") }
    static var editorNew: String { t("editor.title.new") }
    static var editorEdit: String { t("editor.title.edit") }
    static var kind: String { t("editor.kind") }
    static var name: String { t("editor.name") }
    static var shop: String { t("editor.shop") }
    static var country: String { t("editor.country") }
    static var city: String { t("editor.city") }
    static var note: String { t("editor.note") }
    static var save: String { t("editor.save") }
    static var caption: String { t("editor.caption") }
    static var namePlaceholder: String { t("editor.name.placeholder") }
    static var shopPlaceholder: String { t("editor.shop.placeholder") }
    static var countryPlaceholder: String { t("editor.country.placeholder") }
    static var cityPlaceholder: String { t("editor.city.placeholder") }
    static var withoutFooter: String { t("without.footer") }

    static func pending(_ count: Int) -> String { f("collection.pending", count) }
    static func countrySubtitle(cities: Int, visits: Int, buys: Int) -> String {
        f("collection.subtitle", cities, visits, buys)
    }
    static func citySubtitle(visits: Int, buys: Int) -> String { f("country.subtitle", visits, buys) }
    static func shopLine(_ shop: String) -> String { f("entry.shop", shop) }
    static func failureDetail(_ detail: String) -> String { f("failure.detail", detail) }
    static func aiError(_ message: String) -> String { f("settings.ai.error", message) }
    static func bundle(_ id: String) -> String { f("settings.bundle", id) }
    static func group(_ id: String) -> String { f("settings.group", id) }
    static func pendingCount(_ count: Int) -> String { f("settings.pending", count) }

    static func failure(_ code: FailureCode?) -> String {
        switch code {
        case .network: return t("failure.network")
        case .unavailable: return t("failure.unavailable")
        case .emptyCaption: return t("failure.empty")
        case .nothingUseful: return t("failure.nothing")
        case .placesInVideo: return t("failure.video")
        case .blocked: return t("failure.blocked")
        case nil: return t("failure.nothing")
        }
    }
}
