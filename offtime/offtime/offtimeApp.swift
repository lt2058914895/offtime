import SwiftUI

@main
struct offtimeApp: App {
    @StateObject private var appEnvironment = AppEnvironment()
    
    init() {
        setupDatabase()
    }
    
    private func setupDatabase() {
        do {
            try DatabaseRepository.shared.setup()
        } catch {
            fatalError("数据库初始化失败: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appEnvironment)
                .preferredColorScheme(appEnvironment.colorScheme)
                .onChange(of: appEnvironment.settings.themeMode) { _ in
                    // 主题切换时刷新
                }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    
    var body: some View {
        TabView {
            ClockListView()
                .tabItem {
                    Image(systemName: "clock")
                    Text("时钟")
                }
            
            ConverterView()
                .tabItem {
                    Image(systemName: "repeat")
                    Text("转换")
                }
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("设置")
                }
        }
        .onAppear {
            appEnvironment.loadSettings()
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppEnvironment())
}
