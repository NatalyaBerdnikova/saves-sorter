import SwiftUI

@main
struct SavesSorterApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(controller)
                .environmentObject(controller.store)
                .environmentObject(controller.settings)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            NavigationStack {
                CollectionView()
            }
            .tabItem { Label(S.collection, systemImage: "map") }

            NavigationStack {
                ReviewView()
            }
            .tabItem { Label(S.review, systemImage: "checkmark.circle") }
            .modifier(CountBadge(count: store.library.entries.filter(\.needsReview).count))

            NavigationStack {
                UnparsedView()
            }
            .tabItem { Label(S.unparsed, systemImage: "exclamationmark.triangle") }
            .modifier(CountBadge(count: store.library.posts.filter { $0.status == .failed }.count))

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label(S.settings, systemImage: "gearshape") }
        }
        .task { await controller.refreshAndProcess() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await controller.refreshAndProcess() }
            }
        }
    }
}

struct CountBadge: ViewModifier {
    var count: Int

    func body(content: Content) -> some View {
        if count > 0 {
            content.badge(count)
        } else {
            content
        }
    }
}
