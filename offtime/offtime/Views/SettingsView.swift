import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @State private var path = NavigationPath()
    @State private var isPresentingFileExporter = false
    @State private var isPresentingFileImporter = false
    @State private var exportFileURL: URL?
    /// 导入流程：先读取文件数据到内存，再弹确认框让用户选择「合并 / 替换」策略
    @State private var pendingImportData: Data?
    @State private var showImportConfirm = false
    
    /// App Store 真实 ID（由用户提供），用于「分享 App」的分享链接与评分跳转
    private let appStoreID = "6794565774"
    private var appStoreURL: URL { URL(string: "https://apps.apple.com/app/id\(appStoreID)")! }

    /// App Store 写评论页 URL：itms-apps scheme 会直接拉起 App Store app 的写评论界面
    private var writeReviewURL: URL {
        URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review")!
    }

    /// App 显示名：读取 Info.plist 的 CFBundleDisplayName（会自动取当前语言的本地化值，
    /// 中文=世界时钟、英文=OffTime），跟随系统语言，避免硬编码。
    private var appDisplayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "OffTime"
    }

    /// 分享 App 的正文：本地化 App 显示名 + 推荐文案 + 下载链接。
    /// 用纯文本而非 URL：apps.apple.com 链接的 OG 元数据是站点级通用模板（"Today - App Store"），
    /// 无论 ShareLink(item: URL) 还是 UIActivityViewController(items: [url]) 都会被渠道抓成该通用文案；
    /// 纯文本不走 OG 抓取，文案完全可控，链接在文本中仍可点击。
    private var shareAppMessage: String {
        "\(appDisplayName) — \(String(localized: "share.app.body"))\n\(appStoreURL.absoluteString)"
    }

    /// 版本号：读 CFBundleShortVersionString，如 "1.0"
    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// 版本行：info 图标 + 版本号，纯只读展示
    private var versionRow: some View {
        HStack {
            Label(String(localized: "settings.version"), systemImage: "info.circle.fill")
                .foregroundColor(.secondary)
            Spacer()
            Text(versionText)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
    
    var body: some View {
        NavigationStack(path: $path) {
            List {
                // MARK: - 当前城市
                Section(String(localized: "settings.current.city")) {
                    NavigationLink {
                        CitySelectorView(onCitySelected: { city in
                            appEnvironment.switchCurrentCity(city)
                        })
                    } label: {
                        HStack {
                            Image(systemName: "building.2.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                if let name = appEnvironment.settings.currentCityName {
                                    Text(CityDisplay.primaryName(cityName: name, cityEn: appEnvironment.settings.currentCityEn ?? name))
                                        .foregroundColor(.primary)
                                    if let secondary = CityDisplay.secondaryName(cityName: name, cityEn: appEnvironment.settings.currentCityEn ?? name) {
                                        Text(secondary)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Text(String(localized: "settings.current.city.none"))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Section(String(localized: "settings.meetings")) {
                    NavigationLink {
                        MeetingListView()
                    } label: {
                        Label(String(localized: "tab.meeting"), systemImage: "calendar.badge.clock")
                    }
                    NavigationLink {
                        ReminderListView()
                    } label: {
                        Label(String(localized: "reminder.list.title"), systemImage: "bell.fill")
                    }
                }

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
                    .onChange(of: viewModel.themeMode) { _, newMode in
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
                    // 纯文本分享：apps.apple.com URL 的 OG 是通用 "Today - App Store" 模板，
                    // 任何方式分享 URL 都会被抓成该文案；改用纯文本（应用名 + 推荐语 + 链接）绕过 OG。
                    ShareLink(
                        item: shareAppMessage,
                        subject: Text(String(localized: "share.app.subject"))
                    ) {
                        Label(String(localized: "settings.share.app"), systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel(String(localized: "settings.share.app"))

                    // 直接跳 App Store 写评论页：itms-apps scheme 拉起 App Store app，
                    // 不用 in-app 弹窗，确保每次点击都能真正进入评分界面。
                    Button(action: {
                        UIApplication.shared.open(writeReviewURL)
                    }) {
                        HStack {
                            Label(String(localized: "settings.rate.app"), systemImage: "star.fill")
                            Spacer()
                            Text("★★★★★")
                                .foregroundColor(.orange)
                        }
                    }
                    .accessibilityLabel(String(localized: "settings.rate.app"))

                    Button(action: {
                        path.append(AppRoute.supportPage)
                    }) {
                        Label(String(localized: "settings.support"), systemImage: "envelope.fill")
                    }
                }

                // 版本号单独一个 section，纯只读展示
                Section {
                    versionRow
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String(localized: "settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .supportPage:
                    SupportPageView()
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
                        // 先读取数据，再弹确认框让用户选择导入策略，避免直接覆盖现有城市
                        pendingImportData = try Data(contentsOf: url)
                        showImportConfirm = true
                    } catch {
                        viewModel.errorMessage = String(localized: "settings.import.failed")
                    }
                case .failure:
                    viewModel.errorMessage = String(localized: "settings.import.failed")
                }
            }
            .confirmationDialog(
                String(localized: "settings.import.confirm.title"),
                isPresented: $showImportConfirm,
                titleVisibility: .visible
            ) {
                Button(String(localized: "settings.import.merge")) {
                    guard let data = pendingImportData else { return }
                    if viewModel.importCities(from: data, strategy: .merge) {
                        appEnvironment.citiesRevision += 1
                        viewModel.errorMessage = String(localized: "settings.import.success")
                    }
                    pendingImportData = nil
                }
                Button(String(localized: "settings.import.replace"), role: .destructive) {
                    guard let data = pendingImportData else { return }
                    if viewModel.importCities(from: data, strategy: .replace) {
                        appEnvironment.citiesRevision += 1
                        viewModel.errorMessage = String(localized: "settings.import.success")
                    }
                    pendingImportData = nil
                }
                Button(String(localized: "common.cancel"), role: .cancel) {
                    pendingImportData = nil
                }
            } message: {
                Text(String(localized: "settings.import.confirm.message"))
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

// MARK: - Support Page

struct SupportPageView: View {
    private let supportURL = URL(string: "https://lt2058914895.github.io/offtime/support.html")!
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WebView(url: supportURL)
            .navigationTitle(String(localized: "settings.support"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            .toolbar(.hidden, for: .tabBar)
    }
}

#Preview {
    SettingsView()
}
