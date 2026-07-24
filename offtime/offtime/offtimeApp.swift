import SwiftUI

@main
struct offtimeApp: App {
    @StateObject private var appEnvironment = AppEnvironment()
    
    init() {
        // 数据库初始化移至 AppEnvironment.setupDatabase()，避免 fatalError 崩溃
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if appEnvironment.databaseReady == true {
                    MainTabView()
                } else if appEnvironment.databaseReady == false {
                    DatabaseErrorView(errorMessage: appEnvironment.databaseErrorMessage) {
                        appEnvironment.setupDatabase()
                    }
                } else {
                    ProgressView("加载中...")
                }
            }
            .environmentObject(appEnvironment)
            .preferredColorScheme(appEnvironment.colorScheme)
            .onAppear {
                if appEnvironment.databaseReady == nil {
                    appEnvironment.setupDatabase()
                }
            }
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

/// 数据库初始化失败时的错误页面，提供重试按钮
struct DatabaseErrorView: View {
    let errorMessage: String?
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("数据库初始化失败")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(errorMessage ?? "未知错误")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: onRetry) {
                Text("重试")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 120, height: 44)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
            .padding(.top, 8)
        }
        .padding()
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppEnvironment())
}