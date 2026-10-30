import SwiftUI
import Combine
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
                isUnlocked: proAccessService.isUnlocked
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
                .foregroundColor(Color(uiColor: .label).opacity(0.35))
        }
        .accessibilityElement(children: .combine)
    }

    private var settingsList: some View {
        List {
            proSection
            primarySection
            preferencesDataSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: AppRoute.self, destination: handleAppRoute)
        .toast(message: $viewModel.errorMessage)
        .toast(message: proStatusMessageBinding)
        .task {
            viewModel.refreshReminderCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reminderStoreDidChange)) { _ in
            viewModel.refreshReminderCount()
        }
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

    private var primarySection: some View {
        Section {
            Button {
                path.append(AppRoute.citySelector)
            } label: {
                currentCityRow
            }
            .buttonStyle(.plain)

            Button {
                path.append(AppRoute.meetingRecommendation)
            } label: {
                meetingRecommendationRow
            }
            .buttonStyle(.plain)

            Button {
                path.append(AppRoute.reminderList)
            } label: {
                reminderRow
            }
            .buttonStyle(.plain)

            Button {
                path.append(AppRoute.customTheme)
            } label: {
                customThemeRow
            }
            .buttonStyle(.plain)
        }
    }

    private var preferencesDataSection: some View {
        Section {
            Button {
                path.append(AppRoute.addWidgetGuide)
            } label: {
                widgetRow
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

            themePicker

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

    private var aboutSection: some View {
        Section {
            shareAppLink
            rateAppButton
            contactButton
            versionRow
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
                Text(currentCityDisplayName ?? String(localized: "settings.current.city.none"))
                    .foregroundColor(currentCityDisplayName == nil ? .secondary : .primary)

                if let caption = currentCitySecondaryDisplayName {
                    Text(caption)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            settingsChevron
        }
    }

    private var reminderRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .foregroundColor(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "reminder.list.title"))
                    .foregroundColor(.primary)

                Text(String(localized: "settings.reminder.subtitle"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if viewModel.reminderCount > 0 {
                Text(reminderCountText)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            settingsChevron
        }
    }

    private var customThemeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "paintbrush.fill")
                .foregroundColor(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "settings.custom.theme"))
                    .foregroundColor(.primary)

                Text(String(localized: "settings.custom.theme.subtitle"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            ProBadge(showsText: false)

            settingsChevron
        }
    }

    private var meetingRecommendationRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .foregroundColor(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "settings.meeting.recommendation.title"))
                    .foregroundColor(.primary)

                Text(String(localized: "settings.meeting.recommendation.subtitle"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            settingsChevron
        }
    }

    private var currentCityDisplayName: String? {
        guard let names = resolvedCurrentCityNames else { return nil }
        return CityDisplay.primaryName(
            cityName: names.name,
            cityEn: names.en
        )
    }

    private var currentCitySecondaryDisplayName: String? {
        guard let names = resolvedCurrentCityNames else { return nil }
        return CityDisplay.secondaryName(
            cityName: names.name,
            cityEn: names.en
        )
    }

    private var resolvedCurrentCityNames: (name: String, en: String)? {
        guard let name = appEnvironment.settings.currentCityName else { return nil }
        let timezoneId = appEnvironment.settings.currentCityTimezoneId ?? TimeZone.current.identifier
        let matched = CityService.matchCity(cityName: name, timezoneId: timezoneId)
        return (name, appEnvironment.settings.currentCityEn ?? matched.en)
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

    private var reminderCountText: String {
        if viewModel.reminderCount == 1 {
            return String(localized: "reminder.list.count.one")
        }
        return String(
            format: String(localized: "reminder.list.count"),
            viewModel.reminderCount
        )
    }

    private var themePicker: some View {
        Menu {
            ForEach(ThemeMode.allCases) { mode in
                Button {
                    handleThemeChange(mode)
                } label: {
                    if viewModel.themeMode == mode {
                        Text(mode.displayName)
                            + Text(verbatim: "  ")
                            + Text(Image(systemName: "checkmark"))
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

                settingsChevron
            }
        }
        .accessibilityLabel(String(localized: "settings.rate.app"))
    }

    private var contactButton: some View {
        Button {
            path.append(AppRoute.contactPage)
        } label: {
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundColor(.blue)

                Text(String(localized: "settings.contact"))
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
        case .contactPage:
            ContactView()
        case .meetingRecommendation:
            MeetingView(embedsNavigationStack: false)
        case .customTheme:
            CustomThemeSettingsView()
        default:
            EmptyView()
        }
    }

    private func handleThemeChange(_ newMode: ThemeMode) {
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

private struct ProEntryCard: View {
    let title: String
    let actionText: String
    let statusText: String
    let isUnlocked: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var cardBaseColor: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : .clear
    }

    private var cardGradientColors: [Color] {
        colorScheme == .dark
            ? [Color.orange.opacity(0.24), Color.orange.opacity(0.08)]
            : [Color.orange.opacity(0.14), Color.orange.opacity(0.04)]
    }

    private var cardBorderColor: Color {
        let opacity: Double
        switch (colorScheme, isUnlocked) {
        case (.dark, true): opacity = 0.38
        case (.dark, false): opacity = 0.26
        case (_, true): opacity = 0.24
        case (_, false): opacity = 0.14
        }
        return Color.orange.opacity(opacity)
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.orange, .orange.opacity(0.68)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "crown.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 36, height: 36)

            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Text(isUnlocked ? statusText : actionText)
                    .font(.footnote.weight(.semibold))

                Image(systemName: isUnlocked ? "checkmark.circle.fill" : "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Color.orange.opacity(colorScheme == .dark ? 0.20 : 0.12),
                in: Capsule()
            )
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBaseColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: cardGradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.18 : 0.04),
            radius: colorScheme == .dark ? 8 : 5,
            y: colorScheme == .dark ? 3 : 2
        )
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

// MARK: - Contact Page

struct ContactView: View {
    private enum ContactField: Equatable {
        case email
        case wechat
    }

    @Environment(\.dismiss) private var dismiss
    @State private var copiedField: ContactField?

    private let email = "2058914895@qq.com"
    private let wechatID = "SweetLili_91"

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                contactCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(String(localized: "settings.contact"))
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
                .accessibilityLabel(String(localized: "common.back"))
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text(String(localized: "contact.headline"))
                .font(.title3.weight(.semibold))

            Text(String(localized: "contact.subtitle"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var contactCard: some View {
        VStack(spacing: 0) {
            contactRow(
                icon: "at.circle.fill",
                iconColor: .blue,
                label: String(localized: "contact.emailLabel"),
                value: email,
                field: .email,
                copyLabel: String(localized: "contact.copyEmail")
            )

            Divider()
                .padding(.leading, 52)

            contactRow(
                icon: "message.fill",
                iconColor: .green,
                label: String(localized: "contact.wechatLabel"),
                value: wechatID,
                field: .wechat,
                copyLabel: String(localized: "contact.copyWechat")
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func contactRow(
        icon: String,
        iconColor: Color,
        label: String,
        value: String,
        field: ContactField,
        copyLabel: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.body.weight(.medium))
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            Button {
                copy(value, field: field)
            } label: {
                Image(systemName: copiedField == field ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.title3)
                    .foregroundColor(copiedField == field ? .green : .blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copiedField == field ? String(localized: "contact.copied") : copyLabel)
        }
        .padding(16)
    }

    private func copy(_ value: String, field: ContactField) {
        UIPasteboard.general.string = value
        withAnimation(.easeInOut(duration: 0.2)) {
            copiedField = field
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard copiedField == field else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                copiedField = nil
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppEnvironment())
        .environmentObject(ProAccessService())
}
