import SwiftUI
import SwiftData

@main
struct offtimeApp: App {
    @StateObject private var appEnvironment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // iOS 17 起 SwiftUI 的 .tint 不再控制分段控件选中段填充色，
        // 改为通过外观代理统一设置为应用主题色（蓝色）。
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Color.accentColor)
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: UIColor.white],
            for: .selected
        )
    }
    
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
            .onChange(of: scenePhase) { _, phase in
                // 进入后台前补一次发布：改城市时那次刷新请求若被系统合并/丢弃，
                // 用户回到桌面就看不到新城市；这里在有变化时再要一次刷新。
                // 内容没变化时 publish 内部会直接跳过，不会白耗刷新配额。
                if phase == .background {
                    appEnvironment.publishWidgetSnapshot()
                }
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

            ConverterView()
                .tabItem {
                    Image(systemName: "repeat")
                    Text(String(localized: "tab.converter"))
                }
                .tag(AppTab.converter)

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
