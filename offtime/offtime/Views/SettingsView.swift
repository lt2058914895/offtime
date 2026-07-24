import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @State private var path = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("显示设置") {
                    Toggle(isOn: $viewModel.use24Hour) {
                        Text("24小时制")
                    }
                    .onChange(of: viewModel.use24Hour) {
                        viewModel.toggle24Hour()
                        appEnvironment.settings.use24Hour = viewModel.use24Hour
                    }
                    
                    Picker("外观主题", selection: $viewModel.themeMode) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .onChange(of: viewModel.themeMode) { newMode in
                        viewModel.updateTheme(newMode)
                        appEnvironment.settings.themeMode = newMode
                    }
                }
                
                Section("时区数据库") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(viewModel.tzDataVersion)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        viewModel.checkTzDataUpdate()
                    }) {
                        HStack {
                            Text("检查更新")
                            if viewModel.isCheckingUpdate {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                }
                
                Section("数据管理") {
                    Button(action: {
                        exportCities()
                    }) {
                        Text("导出城市列表")
                    }
                    
                    Button(action: {
                        importCities()
                    }) {
                        Text("导入城市列表")
                    }
                }
                
                Section("关于") {
                    Button(action: {
                        path.append(AppRoute.privacyPage)
                    }) {
                        Text("隐私说明")
                    }
                    
                    Button(action: {
                        path.append(AppRoute.aboutPage)
                    }) {
                        Text("关于 OffTime")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .privacyPage:
                    PrivacyPageView()
                case .aboutPage:
                    AboutPageView()
                default:
                    EmptyView()
                }
            }
            .toast(message: $viewModel.errorMessage)
            .toast(message: $viewModel.updateMessage)
        }
    }
    
    private func exportCities() {
        guard let data = viewModel.exportCities() else {
            return
        }
        
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "offtime_cities.json")
        
        do {
            try data.write(to: fileURL)
            
            let activityVC = UIActivityViewController(
                activityItems: [fileURL],
                applicationActivities: nil
            )
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let topViewController = windowScene.windows.first?.rootViewController {
                topViewController.present(activityVC, animated: true)
            }
        } catch {
            viewModel.errorMessage = "导出失败"
        }
    }
    
    private func importCities() {
        let documentPicker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.json],
            asCopy: true
        )
        
        documentPicker.delegate = DocumentPickerDelegate { url in
            do {
                let data = try Data(contentsOf: url)
                if viewModel.importCities(from: data) {
                    viewModel.errorMessage = "导入成功"
                }
            } catch {
                viewModel.errorMessage = "导入失败"
            }
        }
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let topViewController = windowScene.windows.first?.rootViewController {
            topViewController.present(documentPicker, animated: true)
        }
    }
}

class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let completion: (URL) -> Void
    
    init(completion: @escaping (URL) -> Void) {
        self.completion = completion
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            completion(url)
        }
        controller.dismiss(animated: true)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true)
    }
}

struct PrivacyPageView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("隐私说明")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("OffTime 是一款离线世界时钟应用，我们尊重您的隐私。")
                    .font(.body)
                
                Divider()
                
                Text("数据存储")
                    .font(.headline)
                
                Text("所有城市数据和应用设置均存储在您的设备本地，不会上传到任何服务器。")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Divider()
                
                Text("定位权限")
                    .font(.headline)
                
                Text("定位权限仅用于自动检测您所在时区，默认关闭。即使拒绝定位权限，也不影响核心功能使用。")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Divider()
                
                Text("网络请求")
                    .font(.headline)
                
                Text("除手动检查时区数据库更新外，应用不会发起任何网络请求，无埋点、无统计上报。")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .navigationTitle("隐私说明")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct AboutPageView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "globe")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
                
                Text("OffTime")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("离线世界时钟")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Text("版本 1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                Text("简介")
                    .font(.headline)
                
                Text("内置 IANA tzdata 时区数据库，不依赖网络、不依赖网络授时。依靠设备系统时间本地计算时区时间，自动处理夏令时。")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                

            }
            .padding()
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

#Preview {
    SettingsView()
}
