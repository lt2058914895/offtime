import SwiftUI
import SwiftData

struct CustomThemeSettingsView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @EnvironmentObject private var proAccessService: ProAccessService
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CityModel.sortIndex) private var cityModels: [CityModel] = []
    @State private var showProPaywall = false
    @State private var draftTheme: ThemeStyleConfiguration?
    @State private var customBackgroundColor: Color?
    @State private var successMessage: String?

    var body: some View {
        Group {
            if proAccessService.isUnlocked {
                editorContent
            } else {
                lockedContent
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "custom.theme.title"))
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
                .accessibilityLabel(Text(String(localized: "common.back")))
            }

        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showProPaywall) {
            ProPaywallView()
        }
        .toast(message: $successMessage)
    }

    private var editorContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                previewCard
                accentCard
                backgroundCard
                confirmButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .onAppear {
                draftTheme = settings.widgetCustomTheme
                if isCustomBackgroundSelected {
                    customBackgroundColor = editingTheme.backgroundColor?.color
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: editingTheme)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(localized: "custom.theme.preview"))
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button(role: .destructive) {
                    customBackgroundColor = nil
                    updateTheme { $0 = .default }
                } label: {
                    Label(String(localized: "custom.theme.reset"), systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(editingTheme == .default ? Color.secondary : Color.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(editingTheme == .default)
                .accessibilityLabel(Text(String(localized: "custom.theme.reset")))
            }

            WidgetStylePreviewView(
                cities: previewCities,
                localTimezoneId: settings.currentCityTimezoneId ?? TimeZone.current.identifier,
                use24Hour: settings.use24Hour,
                date: appEnvironment.currentDate,
                theme: editingTheme
            )

        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .preferredColorScheme(previewColorScheme ?? systemColorScheme)
    }

    private var accentCard: some View {
        editorCard(title: String(localized: "custom.theme.accent"), systemImage: "paintpalette") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 11) {
                    defaultAccentChip

                    ForEach(ThemeAccentColor.displayOrder) { accentColor in
                        Button {
                            updateTheme {
                                $0.accentColor = accentColor
                                $0.customAccentColor = nil
                            }
                        } label: {
                            ThemeColorChip(
                                color: accentColor.color,
                                isSelected: editingTheme.accentColor == accentColor
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accentColor.displayName)
                    }

                    customAccentChip
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
    }

    private var defaultAccentChip: some View {
        Button {
            updateTheme {
                $0.accentColor = nil
                $0.customAccentColor = nil
            }
        } label: {
            ThemeColorChip(color: nil, isSelected: editingTheme.accentColor == nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "custom.theme.accent.default"))
    }

    private var customAccentChip: some View {
        ThemeColorChip(
            color: editingTheme.customAccentColor?.color,
            isSelected: editingTheme.accentColor == .custom,
            showsCheckmark: false
        )
            .overlay {
                ColorPicker(
                    String(localized: "custom.theme.accent.custom"),
                    selection: Binding(
                        get: { editingTheme.customAccentColor?.color ?? .white },
                        set: { color in
                            updateTheme {
                                $0.accentColor = .custom
                                $0.customAccentColor = ThemeColor(color: color)
                            }
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
            }
            .overlay {
                if editingTheme.accentColor == .custom {
                    ThemeColorCheckmark(color: editingTheme.customAccentColor?.color)
                }
            }
            .accessibilityLabel(String(localized: "custom.theme.accent.custom"))
    }

    private var backgroundCard: some View {
        editorCard(title: String(localized: "custom.theme.background"), systemImage: "square.fill.on.square.fill") {
            VStack(alignment: .leading, spacing: 12) {
                backgroundOptionRow(title: String(localized: "custom.theme.background.color")) {
                    defaultBackgroundChip

                    ForEach(ThemeBackgroundOption.allCases) { option in
                        backgroundChip(for: option)
                    }

                    customBackgroundPicker
                }

                backgroundOptionRow(title: String(localized: "custom.theme.background.photo")) {
                    ForEach(ThemeBackgroundPhoto.allCases) { photo in
                        backgroundPhotoChip(for: photo)
                    }
                }
            }
        }
    }

    private func backgroundOptionRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    content()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
    }

    private var defaultBackgroundChip: some View {
        Button {
            customBackgroundColor = nil
            updateTheme {
                $0.backgroundColor = nil
                $0.backgroundPhoto = nil
            }
        } label: {
            ThemeColorChip(color: nil, isSelected: isDefaultBackgroundSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "custom.theme.background.default"))
    }

    private func backgroundChip(for option: ThemeBackgroundOption) -> some View {
        Button {
            customBackgroundColor = nil
            updateTheme {
                $0.backgroundColor = ThemeColor(color: option.color)
                $0.backgroundPhoto = nil
            }
        } label: {
            ThemeColorChip(
                color: option.color,
                isSelected: isSelected(option.color)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName)
    }

    private var customBackgroundPicker: some View {
        ThemeColorChip(
            color: customBackgroundColor,
            isSelected: isCustomBackgroundSelected,
            showsCheckmark: false
        )
            .overlay {
                ColorPicker(
                    String(localized: "custom.theme.background.custom"),
                    selection: Binding(
                        get: { customBackgroundColor ?? .white },
                        set: { color in
                            customBackgroundColor = color
                            updateTheme {
                                $0.backgroundColor = ThemeColor(color: color)
                                $0.backgroundPhoto = nil
                            }
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
            }
            .overlay {
                if isCustomBackgroundSelected {
                    ThemeColorCheckmark(color: customBackgroundColor)
                }
            }
        .accessibilityLabel(String(localized: "custom.theme.background.custom"))
    }

    private func backgroundPhotoChip(for photo: ThemeBackgroundPhoto) -> some View {
        Button {
            customBackgroundColor = nil
            updateTheme {
                $0.backgroundColor = nil
                $0.backgroundPhoto = photo
            }
        } label: {
            ThemeWidgetBackground(photo: photo)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    if editingTheme.backgroundPhoto == photo {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                }
                .modifier(PhotoSelectionBorder(isSelected: editingTheme.backgroundPhoto == photo))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(photo.displayName)
    }

    private var confirmButton: some View {
        Button {
            update { settings in
                settings.widgetCustomTheme = editingTheme
            }

            successMessage = String(localized: "custom.theme.saved.success")
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                dismiss()
            }
        } label: {
            Text(String(localized: "custom.theme.confirm"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(
                    hasUnconfirmedChanges ? Color.accentColor : Color.accentColor.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!hasUnconfirmedChanges)
    }

    private var lockedContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)

                Text(String(localized: "custom.theme.pro.title"))
                    .font(.headline)

                Text(String(localized: "custom.theme.pro.detail"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    showProPaywall = true
                } label: {
                    Text(String(localized: "custom.theme.unlock"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(16)
        }
    }

    private var settings: AppSettings { appEnvironment.settings }

    private var editingTheme: ThemeStyleConfiguration {
        draftTheme ?? settings.widgetCustomTheme
    }

    private var hasUnconfirmedChanges: Bool {
        guard let draftTheme else { return false }
        return draftTheme != settings.widgetCustomTheme
    }

    private var previewColorScheme: ColorScheme? {
        switch settings.themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var previewCities: [WidgetCitySnapshot] {
        let localTimezoneId = settings.currentCityTimezoneId ?? TimeZone.current.identifier

        return cityModels.map { city in
            WidgetCitySnapshot(
                id: city.id.uuidString,
                cityName: city.cityName,
                cityEn: city.cityEn,
                countryCode: city.country,
                timezoneId: city.timezoneId,
                workStartHour: city.workStartHour,
                workEndHour: city.workEndHour,
                isLocal: city.timezoneId == localTimezoneId
            )
        }
    }

    private func editorCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func isSelected(_ color: Color) -> Bool {
        guard let selectedColor = editingTheme.backgroundColor else { return false }
        return selectedColor == ThemeColor(color: color)
    }

    private var isDefaultBackgroundSelected: Bool {
        editingTheme.backgroundColor == nil && editingTheme.backgroundPhoto == nil
    }

    private var isCustomBackgroundSelected: Bool {
        guard editingTheme.backgroundColor != nil, editingTheme.backgroundPhoto == nil else {
            return false
        }

        return !ThemeBackgroundOption.allCases.contains { isSelected($0.color) }
    }

    private func updateTheme(_ transform: (inout ThemeStyleConfiguration) -> Void) {
        guard proAccessService.isUnlocked else {
            showProPaywall = true
            return
        }

        var theme = editingTheme
        transform(&theme)
        draftTheme = theme
    }

    private func update(_ transform: (inout AppSettings) -> Void) {
        guard proAccessService.isUnlocked else {
            showProPaywall = true
            return
        }

        var settings = appEnvironment.settings
        transform(&settings)
        appEnvironment.updateSettings(settings)
    }
}

private enum ThemeBackgroundOption: CaseIterable, Identifiable {
    case cream
    case mint
    case sky
    case lavender
    case blush
    case charcoal

    var id: Self { self }

    var color: Color {
        switch self {
        case .cream: return Color(red: 0.99, green: 0.96, blue: 0.89)
        case .mint: return .mint.opacity(0.28)
        case .sky: return .blue.opacity(0.20)
        case .lavender: return .purple.opacity(0.18)
        case .blush: return .pink.opacity(0.18)
        case .charcoal: return Color(red: 0.15, green: 0.17, blue: 0.20)
        }
    }

    var displayName: String {
        switch self {
        case .cream: return String(localized: "theme.background.cream")
        case .mint: return String(localized: "theme.background.mint")
        case .sky: return String(localized: "theme.background.sky")
        case .lavender: return String(localized: "theme.background.lavender")
        case .blush: return String(localized: "theme.background.blush")
        case .charcoal: return String(localized: "theme.background.charcoal")
        }
    }

}

private struct ThemeColorChip: View {
    let color: Color?
    let isSelected: Bool
    var showsCheckmark: Bool = true

    var body: some View {
        Circle()
            .fill(color ?? Color(.secondarySystemBackground))
            .frame(width: 34, height: 34)
            .overlay {
                if showsCheckmark, isSelected {
                    ThemeColorCheckmark(color: color)
                } else if color == nil {
                    Image(systemName: "circle.slash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .overlay {
                if isSelected {
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                } else {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
    }
}

private struct ThemeColorCheckmark: View {
    let color: Color?

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle((color?.isLight ?? true) ? Color.black : Color.white)
            .shadow(color: .black.opacity((color?.isLight ?? true) ? 0 : 0.35), radius: 2)
    }
}

private extension Color {
    var isLight: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return true
        }

        let luminance = (red * 0.299 + green * 0.587 + blue * 0.114) * alpha + (1 - alpha)
        return luminance > 0.62
    }
}

private struct PhotoSelectionBorder: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: 2
                )
        }
    }
}
