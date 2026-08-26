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
