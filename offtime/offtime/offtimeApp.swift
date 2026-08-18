import SwiftUI
import SwiftData

@main
struct offtimeApp: App {
    @StateObject private var appEnvironment = AppEnvironment()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if appEnvironment.onboardingCompleted {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(appEnvironment)
            .modelContainer(appEnvironment.modelContainer)
            .preferredColorScheme(appEnvironment.colorScheme)
            .onAppear {
                appEnvironment.setup()
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @State private var selectedTab: AppTab = .clock

    var body: some View {
        TabView(selection: $selectedTab) {
            ClockListView(activeTab: $selectedTab)
                .tabItem {
                    Image(systemName: "clock")
                    Text(String(localized: "tab.clock"))
                }
                .tag(AppTab.clock)

            MeetingView()
                .tabItem {
                    Image(systemName: "person.2")
                    Text(String(localized: "tab.meeting"))
                }
                .tag(AppTab.meeting)

            TravelView()
                .tabItem {
                    Image(systemName: "airplane")
                    Text(String(localized: "tab.travel"))
                }
                .tag(AppTab.travel)

            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text(String(localized: "tab.settings"))
                }
                .tag(AppTab.settings)
        }
        .modifier(SidebarAdaptableTabStyle())
        .onAppear {
            appEnvironment.loadSettings()
        }
    }
}

/// iOS 18+ iPad 侧边栏 Tab 样式，iOS 17 使用默认样式
struct SidebarAdaptableTabStyle: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), horizontalSizeClass == .regular {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppEnvironment())
        .modelContainer(for: CityModel.self, inMemory: true)
}
