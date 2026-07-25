import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @State private var path = NavigationPath()
    @State private var isPresentingFileExporter = false
    @State private var isPresentingFileImporter = false
    @State private var exportFileURL: URL?
    
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
                }
                
                Section("数据管理") {
                    Button(action: {
                        prepareExportFile()
                        isPresentingFileExporter = true
                    }) {
                        Text("导出城市列表")
                    }
                    
                    Button(action: {
                        isPresentingFileImporter = true
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
                        path.append(AppRoute.supportPage)
                    }) {
                        Text("问题反馈")
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
                case .supportPage:
                    SupportPageView()
                case .aboutPage:
                    AboutPageView()
                default:
                    EmptyView()
                }
            }
            .toast(message: $viewModel.errorMessage)
            // SwiftUI 原生文件导出
            .fileExporter(
                isPresented: $isPresentingFileExporter,
                document: exportFileURL.map { JSONFileDocument(fileURL: $0) } ?? JSONFileDocument(fileURL: URL(fileURLWithPath: "/dev/null")),
                contentType: UTType.json,
                defaultFilename: "offtime_cities"
            ) { result in
                switch result {
                case .success:
                    viewModel.errorMessage = "导出成功"
                case .failure(let error):
                    viewModel.errorMessage = "导出失败: \(error.localizedDescription)"
                }
                // 清理临时文件
                if let url = exportFileURL {
                    try? FileManager.default.removeItem(at: url)
                    exportFileURL = nil
                }
            }
            // SwiftUI 原生文件导入
            .fileImporter(
                isPresented: $isPresentingFileImporter,
                allowedContentTypes: [UTType.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        let data = try Data(contentsOf: url)
                        if viewModel.importCities(from: data) {
                            viewModel.errorMessage = "导入成功"
                        }
                    } catch {
                        viewModel.errorMessage = "导入失败，文件格式错误"
                    }
                case .failure:
                    viewModel.errorMessage = "导入失败"
                }
            }
        }
    }
    
    private func prepareExportFile() {
        guard let data = viewModel.exportCities() else {
            viewModel.errorMessage = "导出失败"
            return
        }
        
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "offtime_cities.json")
        do {
            try data.write(to: fileURL)
            exportFileURL = fileURL
        } catch {
            viewModel.errorMessage = "导出失败"
        }
    }
}

// MARK: - JSONFileDocument for SwiftUI fileExporter

struct JSONFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var fileURL: URL
    
    init(fileURL: URL) {
        self.fileURL = fileURL
    }
    
    init(configuration: ReadConfiguration) throws {
        fileURL = URL(fileURLWithPath: "/dev/null")
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try Data(contentsOf: fileURL)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - WebView Wrapper

import WebKit

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator()
    }

    class WebViewCoordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showError(webView, error: error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showError(webView, error: error)
        }

        private func showError(_ webView: WKWebView, error: Error) {
            let nsError = error as NSError
            guard nsError.domain == NSURLErrorDomain else { return }
            DispatchQueue.main.async {
                let html = """
                <!DOCTYPE html>
                <html lang="zh-CN">
                <head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
                <style>
                    body{font-family:-apple-system,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#f5f5f5;color:#333;}
                    .box{text-align:center;padding:40px 24px;}
                    .icon{font-size:48px;margin-bottom:16px;}
                    h2{font-size:18px;font-weight:600;margin-bottom:8px;}
                    p{font-size:14px;color:#999;line-height:1.6;}
                </style></head>
                <body><div class="box">
                    <div class="icon">📡</div>
                    <h2>无法加载页面</h2>
                    <p>请检查网络连接后重试</p>
                </div></body></html>
                """
                webView.loadHTMLString(html, baseURL: nil)
            }
        }
    }
}

// MARK: - Privacy & About Pages

struct PrivacyPageView: View {
    private let privacyURL = URL(string: "https://lt2058914895.github.io/offtime/privacy.html")!

    var body: some View {
        WebView(url: privacyURL)
            .navigationTitle("隐私说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
    }
}

struct SupportPageView: View {
    private let supportURL = URL(string: "https://lt2058914895.github.io/offtime/support.html")!

    var body: some View {
        WebView(url: supportURL)
            .navigationTitle("问题反馈")
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
                
                Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
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