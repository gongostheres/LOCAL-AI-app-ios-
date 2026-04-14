import SwiftUI

struct ContentView: View {
    @State private var libraryVM = ModelLibraryViewModel()
    @State private var chatVM = ChatViewModel()
    @State private var selectedTab = 0
    @AppStorage("onboardingDone") private var onboardingDone = false

    var body: some View {
        Group {
            if !onboardingDone {
                OnboardingView(isDone: $onboardingDone)
                    .transition(.opacity)
            } else {
                mainTabs
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: onboardingDone)
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            ChatView(selectedTab: $selectedTab)
                .tabItem { Label("Чат", systemImage: "bubble.left.and.bubble.right") }
                .tag(0)

            ModelLibraryView(selectedTab: $selectedTab)
                .tabItem { Label("Модели", systemImage: "cpu") }
                .badge(libraryVM.downloadedModels.isEmpty ? "!" : nil)
                .tag(1)
        }
        .environment(libraryVM)
        .environment(chatVM)
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in }
    }
}
