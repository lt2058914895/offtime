import Foundation

/// 城市唯一身份标识：用于城市目录与「已添加城市列表」的准确去重。
/// 身份键 = 「规范化英文名 + IANA 时区」；中文名仅作展示，不参与判重，
/// 因此同名不同城（如 福州/抚州）不会被误判，同城不同译名（如 金奈/钦奈）也能被识别。
enum CityIdentity {
    /// 历史/跨语言同义词 → 规范英文名（归一化后再映射）
    static let aliases: [String: String] = [
        "madras": "chennai",
        "bombay": "mumbai",
        "calcutta": "kolkata",
        "peking": "beijing",
        "rangoon": "yangon",
        "saigon": "hochiminhcity",
        "canton": "guangzhou",
    ]

    /// 规范化英文名：小写、去变音符、仅保留字母数字
    static func normalizedEnglishName(_ name: String) -> String {
        let folded = name.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let base = folded
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
        return aliases[base] ?? base
    }

    /// 稳定身份键：normalizedEn|timezoneId
    static func key(cityEn: String, timezoneId: String) -> String {
        "\(normalizedEnglishName(cityEn))|\(timezoneId)"
    }
}

/// 城市名本地化显示工具：根据 App 当前语言动态选择主/副显示名。
/// 中文环境 → cityName 为主、cityEn 为副；非中文环境 → cityEn 为主、cityName 为副。
enum CityDisplay {
    /// App 实际使用的本地化语言是否为中文
    static var isChineseLocale: Bool {
        Bundle.main.preferredLocalizations.first?.hasPrefix("zh") ?? false
    }

    /// 主显示名：中文环境返回 cityName，非中文环境返回 cityEn
    static func primaryName(cityName: String, cityEn: String) -> String {
        isChineseLocale ? cityName : cityEn
    }

    /// 副显示名：仅中文环境下返回英文名作为副名；非中文环境返回 nil（只显示英文名）
    static func secondaryName(cityName: String, cityEn: String) -> String? {
        guard isChineseLocale, cityName != cityEn else { return nil }
        return cityEn
    }
}
