import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @EnvironmentObject private var proAccessService: ProAccessService
    @State private var path = NavigationPath()
    @State private var isPresentingFileExporter = false
    @State private var isPresentingFileImporter = false
    @State private var exportFileURL: URL?
    /// 导入流程：先读取文件数据到内存，再弹确认框让用户选择「合并 / 替换」策略
    @State private var pendingImportData: Data?
    @State private var showImportConfirm = false
    @State private var showProPaywall = false
    
    /// App Store 真实 ID（由用户提供），用于「分享 App」的分享链接与评分跳转
    private let appStoreID = "6794565774"
    private var appStoreURL: URL { URL(string: "https://apps.apple.com/app/id\(appStoreID)")! }

    /// App Store 写评论页 URL：itms-apps scheme 会直接拉起 App Store app 的写评论界面
    private var writeReviewURL: URL {
        URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review")!
    }

    /// 分享 App 的正文：本地化 App 显示名 + 推荐文案 + 下载链接。
    /// 用纯文本而非 URL：apps.apple.com 链接的 OG 元数据是站点级通用模板（"Today - App Store"），
    /// 无论 ShareLink(item: URL) 还是 UIActivityViewController(items: [url]) 都会被渠道抓成该通用文案；
    /// 纯文本不走 OG 抓取，文案完全可控，链接在文本中仍可点击。
    private var shareAppMessage: String {
        "\(AppDisplay.name) — \(String(localized: "share.app.body"))\n\(appStoreURL.absoluteString)"
    }

    /// 版本号：读 CFBundleShortVersionString，如 "1.0"
    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var proSectionContent: some View {
        Button {
            showProPaywall = true
        } label: {
            ProEntryCard(
                title: proAccessService.displayTitle,
                actionText: String(localized: "pro.entry.action"),
                statusText: String(localized: "pro.status.unlocked"),
                isUnlocked: proAccessService.isUnlocked,
                legacyHintText: proAccessService.isLegacyUnlocked
                    ? String(localized: "pro.status.legacy.hint")
                    : nil
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    /// 版本行：info 图标 + 版本号，纯只读展示
    private var versionRow: some View {
        HStack {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)

            Text(String(localized: "settings.version"))
                .foregroundColor(.primary)

            Spacer()
            Text(versionText)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var settingsList: some View {
        List {
            proSection
            meetingSection
            generalSection
            displaySection
            dataManagementSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: AppRoute.self, destination: handleAppRoute)
        .toast(message: $viewModel.errorMessage)
        .toast(message: proStatusMessageBinding)
        .sheet(isPresented: $showProPaywall) {
            ProPaywallView()
        }
        .fileExporter(
            isPresented: $isPresentingFileExporter,
            document: exportDocument,
            contentType: UTType.json,
            defaultFilename: "offtime_cities"
        ) { result in
            handleExportResult(result)
        }
        .fileImporter(
            isPresented: $isPresentingFileImporter,
            allowedContentTypes: [UTType.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .confirmationDialog(
            String(localized: "settings.import.confirm.title"),
            isPresented: $showImportConfirm,
            titleVisibility: .visible
        ) {
            importConfirmationButtons
        } message: {
            Text(String(localized: "settings.import.confirm.message"))
        }
    }

    private var proSection: some View {
        Section {
            proSectionContent
        }
    }

    private var meetingSection: some View {
        Section {
            meetingSectionContent
        }
    }

    private var meetingSectionContent: some View {
        Button {
            path.append(AppRoute.meetingRecommendation)
        } label: {
            MeetingRecommendationCard()
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    private var generalSection: some View {
        Section(String(localized: "settings.general.section")) {
            Button {
                path.append(AppRoute.citySelector)
            } label: {
                currentCityRow
            }
            .buttonStyle(.plain)

            Button {
                path.append(AppRoute.reminderList)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.blue)
                        .font(.title3)

                    Text(String(localized: "reminder.list.title"))
                        .foregroundColor(.primary)

                    Spacer()

                    settingsChevron
                }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .foregroundColor(.blue)
                    .font(.title3)

                Text(String(localized: "settings.24hour"))

                Spacer()

                Toggle(String(localized: "settings.24hour"), isOn: $viewModel.use24Hour)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .onChange(of: viewModel.use24Hour) {
                viewModel.toggle24Hour()
                appEnvironment.settings.use24Hour = viewModel.use24Hour
            }
        }
    }

    private var displaySection: some View {
        Section(String(localized: "settings.accessibility.section")) {
            Button {
                path.append(AppRoute.addWidgetGuide)
            } label: {
                widgetRow
            }
            .buttonStyle(.plain)

            customThemeRow

            themePicker
        }
    }

    private var dataManagementSection: some View {
        Section(String(localized: "settings.data.section")) {
            Button {
                prepareExportFile()
                isPresentingFileExporter = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up.fill")
                        .foregroundColor(.blue)
                        .font(.title3)

                    Text(String(localized: "settings.export.cities"))
                        .foregroundColor(.primary)

                    Spacer()

                    settingsChevron
                }
            }

            Button {
                isPresentingFileImporter = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .foregroundColor(.blue)
                        .font(.title3)

                    Text(String(localized: "settings.import.cities"))
                        .foregroundColor(.primary)

                    Spacer()

                    settingsChevron
                }
            }
        }
    }

    private var currentCityRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .foregroundColor(.blue)
                .font(.title3)

            Text(String(localized: "settings.current.city"))
                .foregroundColor(.primary)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
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
            settingsChevron
                .contentShape(Rectangle())
        }
    }

    private var widgetRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill")
                .foregroundColor(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "settings.add.widget"))
                    .foregroundColor(.primary)

                Text(AppDisplay.text("settings.add.widget.subtitle", AppDisplay.name))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()

            settingsChevron
                .contentShape(Rectangle())
        }
    }

    private var settingsChevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundColor(Color(uiColor: .tertiaryLabel))
    }

    private var themePicker: some View {
        Menu {
            ForEach(ThemeMode.allCases) { mode in
                Button {
                    handleThemeChange(mode)
                } label: {
                    if viewModel.themeMode == mode {
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "paintpalette.fill")
                    .foregroundColor(.blue)
                    .font(.title3)

                Text(String(localized: "settings.theme.section"))
                    .foregroundColor(.primary)

                Spacer()

                Text(viewModel.themeMode.displayName)
                    .foregroundColor(.secondary)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
            }
        }
    }

    private var customThemeRow: some View {
        Button {
            path.append(AppRoute.customTheme)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "paintbrush.fill")
                    .foregroundColor(.blue)
                    .font(.title3)

                Text(String(localized: "settings.custom.theme"))

                Spacer()

                if !proAccessService.isUnlocked {
                    ProBadge()
                }

                settingsChevron
            }
        }
        .buttonStyle(.plain)
    }

    private var aboutSection: some View {
        Section(String(localized: "settings.about")) {
            shareAppLink
            rateAppButton
            supportButton
            versionRow
        }
    }

    private var shareAppLink: some View {
        ShareLink(
            item: shareAppMessage,
            subject: Text(String(localized: "share.app.subject"))
        ) {
            HStack {
                Image(systemName: "arrowshape.turn.up.right.fill")
                    .foregroundColor(.blue)

                Text(String(localized: "settings.share.app"))
                    .foregroundColor(.primary)

                Spacer()

                settingsChevron
            }
        }
        .accessibilityLabel(String(localized: "settings.share.app"))
    }

    private var rateAppButton: some View {
        Button {
            UIApplication.shared.open(writeReviewURL)
        } label: {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.blue)

                Text(String(localized: "settings.rate.app"))
                    .foregroundColor(.primary)

                Spacer()
                Text("★★★★★")
                    .foregroundColor(.orange)

                settingsChevron
            }
        }
        .accessibilityLabel(String(localized: "settings.rate.app"))
    }

    private var supportButton: some View {
        Button {
            path.append(AppRoute.supportPage)
        } label: {
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundColor(.blue)

                Text(String(localized: "settings.support"))
                    .foregroundColor(.primary)

                Spacer()

                settingsChevron
            }
        }
        }

    private var proStatusMessageBinding: Binding<String?> {
        Binding(
            get: { proAccessService.statusMessage },
            set: { _ in proAccessService.statusMessage = nil }
        )
    }

    private var exportDocument: JSONFileDocument {
        JSONFileDocument(
            fileURL: exportFileURL ?? URL(fileURLWithPath: "/dev/null")
        )
    }

    @ViewBuilder
    private var importConfirmationButtons: some View {
        Button(String(localized: "settings.import.merge")) {
            importCities(strategy: .merge)
        }

        Button(String(localized: "settings.import.replace"), role: .destructive) {
            importCities(strategy: .replace)
        }

        Button(String(localized: "common.cancel"), role: .cancel) {
            pendingImportData = nil
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            settingsList
        }
    }

    @ViewBuilder
    private func handleAppRoute(_ route: AppRoute) -> some View {
        switch route {
        case .citySelector:
            CitySelectorView(onCitySelected: { city in
                appEnvironment.switchCurrentCity(city)
            })
        case .reminderList:
            ReminderListView()
        case .addWidgetGuide:
            AddWidgetGuideView()
        case .supportPage:
            SupportPageView()
        case .meetingRecommendation:
            MeetingView(embedsNavigationStack: false)
        case .customTheme:
            CustomThemeSettingsView()
        default:
            EmptyView()
        }
    }

    private func handleThemeChange(_ newMode: ThemeMode) {
        guard ProAccessPolicy.isThemeUnlocked(
            newMode,
            isUnlocked: proAccessService.isUnlocked
        ) else {
            showProPaywall = true
            viewModel.themeMode = appEnvironment.settings.themeMode
            return
        }

        viewModel.updateTheme(newMode)
        var settings = appEnvironment.settings
        settings.themeMode = newMode
        appEnvironment.updateSettings(settings)
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            viewModel.errorMessage = String(localized: "settings.export.success")
        case .failure(let error):
            viewModel.errorMessage = String(localized: "settings.export.failed") + ": \(error.localizedDescription)"
        }

        if let url = exportFileURL {
            try? FileManager.default.removeItem(at: url)
            exportFileURL = nil
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                pendingImportData = try Data(contentsOf: url)
                showImportConfirm = true
            } catch {
                viewModel.errorMessage = String(localized: "settings.import.failed")
            }
        case .failure:
            viewModel.errorMessage = String(localized: "settings.import.failed")
        }
    }

    private func importCities(strategy: ImportStrategy) {
        guard let data = pendingImportData else { return }
        if viewModel.importCities(from: data, strategy: strategy) {
            appEnvironment.citiesRevision += 1
            viewModel.errorMessage = String(localized: "settings.import.success")
        }
        pendingImportData = nil
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

private struct MeetingRecommendationCard: View {
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.68)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "calendar.badge.clock")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "settings.meeting.recommendation.title"))
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(String(localized: "settings.meeting.recommendation.subtitle"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())

        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.12), Color.accentColor.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

private struct ProEntryCard: View {
    let title: String
    let actionText: String
    let statusText: String
    let isUnlocked: Bool
    let legacyHintText: String?

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [.orange, .orange.opacity(0.68)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "crown.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 8)

                    HStack(spacing: 4) {
                        Text(isUnlocked ? statusText : actionText)
                            .font(.subheadline.weight(.semibold))

                        Image(systemName: isUnlocked ? "checkmark.circle.fill" : "chevron.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12), in: Capsule())
                    .fixedSize()

                }

                if let legacyHintText {
                    Text(legacyHintText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.14), Color.orange.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.orange.opacity(isUnlocked ? 0.24 : 0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
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
                            .fontWeight(.semibold)
                    }
                }
            }
            .toolbar(.hidden, for: .tabBar)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppEnvironment())
        .environmentObject(ProAccessService())
}
