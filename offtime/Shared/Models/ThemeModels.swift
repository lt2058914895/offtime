import SwiftUI

enum ThemeAccentColor: Int, Codable, Hashable, CaseIterable, Identifiable {
    case blue = 0
    case purple = 1
    case green = 2
    case orange = 3
    case red = 4
    case teal = 5
    case white = 8
    case custom = 9

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .blue: return String(localized: "theme.accent.blue")
        case .purple: return String(localized: "theme.accent.purple")
        case .green: return String(localized: "theme.accent.green")
        case .orange: return String(localized: "theme.accent.orange")
        case .red: return String(localized: "theme.accent.red")
        case .teal: return String(localized: "theme.accent.teal")
        case .white: return String(localized: "theme.accent.white")
        case .custom: return String(localized: "custom.theme.accent.custom")
        }
    }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .teal: return .teal
        case .white: return .white
        case .custom: return .clear
        }
    }

    static var displayOrder: [ThemeAccentColor] {
        [.white, .blue, .purple, .green, .orange, .red, .teal]
    }
}

struct ThemeStyleConfiguration: Codable, Hashable {
    var accentColor: ThemeAccentColor?
    var customAccentColor: ThemeColor?
    var backgroundColor: ThemeColor?
    var backgroundPhoto: ThemeBackgroundPhoto?

    static let `default` = ThemeStyleConfiguration(
        accentColor: nil,
        customAccentColor: nil,
        backgroundColor: nil,
        backgroundPhoto: nil
    )

    var resolvedAccentColor: Color? {
        switch accentColor {
        case .custom:
            return customAccentColor?.color
        case let accentColor?:
            return accentColor.color
        case nil:
            return nil
        }
    }
}

enum ThemeBackgroundPhoto: Int, Codable, Hashable, CaseIterable, Identifiable {
    case sunset = 0
    case ocean = 1
    case forest = 2
    case aurora = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .sunset: return String(localized: "theme.background.photo.sunset")
        case .ocean: return String(localized: "theme.background.photo.ocean")
        case .forest: return String(localized: "theme.background.photo.forest")
        case .aurora: return String(localized: "theme.background.photo.aurora")
        }
    }

    var imageName: String {
        switch self {
        case .sunset: return "WidgetPhotoSunset"
        case .ocean: return "WidgetPhotoOcean"
        case .forest: return "WidgetPhotoForest"
        case .aurora: return "WidgetPhotoAurora"
        }
    }
}

struct ThemeColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init(color: Color) {
        let resolved = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var opacity: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &opacity)

        self.red = Double(red)
        self.green = Double(green)
        self.blue = Double(blue)
        self.opacity = Double(opacity)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct ThemeWidgetBackground: View {
    let color: ThemeColor?
    let photo: ThemeBackgroundPhoto?

    init(
        color: ThemeColor? = nil,
        photo: ThemeBackgroundPhoto? = nil
    ) {
        self.color = color
        self.photo = photo
    }

    @ViewBuilder
    var body: some View {
        ZStack {
            if let photo {
                Image(photo.imageName)
                    .resizable()
                    .scaledToFill()

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.28),
                        Color.black.opacity(0.04),
                        Color.black.opacity(0.18),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if let color {
                color.color
            } else {
                Color(.secondarySystemBackground)
            }
        }
        .clipped()
    }
}
