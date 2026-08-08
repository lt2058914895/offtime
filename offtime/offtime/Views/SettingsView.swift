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
                Section(String(localized: "settings.display")) {
                    Toggle(isOn: $viewModel.use24Hour) {
                        Text(String(localized: "settings.24hour"))
                    }
                    .onChange(of: viewModel.use24Hour) {
                        viewModel.toggle24Hour()
                        appEnvironment.settings.use24Hour = viewModel.use24Hour
                    }
                    
                    Picker(String(localized: "settings.theme"), selection: $viewModel.themeMode) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .onChange(of: viewModel.themeMode) { newMode in
                        viewModel.updateTheme(newMode)
                        appEnvironment.settings.themeMode = newMode
                    }
                }
                
                Section(String(localized: "settings.data.management")) {
                    Button(action: {
                        prepareExportFile()
                        isPresentingFileExporter = true
                    }) {
                        Text(String(localized: "settings.export.cities"))
                    }
                    
                    Button(action: {
                        isPresentingFileImporter = true
                    }) {
                        Text(String(localized: "settings.import.cities"))
                    }
                }
                
                Section(String(localized: "settings.about")) {
                    Button(action: {
                        path.append(AppRoute.privacyPage)
                    }) {
                        Text(String(localized: "settings.privacy"))
                    }
                    
                    Button(action: {
                        path.append(AppRoute.supportPage)
                    }) {
                        Text(String(localized: "settings.support"))
                    }
                    
                    Button(action: {
                        path.append(AppRoute.aboutPage)
                    }) {
                        Text(String(localized: "settings.about.offtime"))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String(localized: "settings.title"))
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
                    viewModel.errorMessage = String(localized: "settings.export.success")
                case .failure(let error):
                    viewModel.errorMessage = String(localized: "settings.export.failed") + ": \(error.localizedDescription)"
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
                            viewModel.errorMessage = String(localized: "settings.import.success")
                        }
                    } catch {
                        viewModel.errorMessage = String(localized: "settings.import.failed")
                    }
                case .failure:
                    viewModel.errorMessage = String(localized: "settings.import.failed")
                }
            }
        }
    }
    
    private func prepareExportFile() {
        guard let data = viewModel.exportCities() else {
            viewModel.errorMessage = String(localized: "settings.export.failed")
            return
        }
        
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "offtime_cities.json")
        do {
            try data.write(to: fileURL)
            exportFileURL = fileURL
        } catch {
            viewModel.errorMessage = String(localized: "settings.export.failed")
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
                <html lang="en">
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
                    <h2>\(String(localized: "web.load.failed"))</h2>
                    <p>\(String(localized: "web.check.network"))</p>
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
            .navigationTitle(String(localized: "settings.privacy"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
    }
}

struct SupportPageView: View {
    private let supportURL = URL(string: "https://lt2058914895.github.io/offtime/support.html")!

    var body: some View {
        WebView(url: supportURL)
            .navigationTitle(String(localized: "settings.support"))
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
                
                Text(String(localized: "about.offtime"))
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Text("\(String(localized: "settings.version")) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                Text(String(localized: "about.intro"))
                    .font(.headline)
                
                Text(String(localized: "about.description"))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle(String(localized: "about.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

#Preview {
    SettingsView()
}