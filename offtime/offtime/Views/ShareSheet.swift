import SwiftUI
import UIKit

/// 系统分享面板包装：用于上下文菜单、设置页等需要 `UIActivityViewController` 的场景。
/// 直接把 item 交给系统，由各渠道（微信/Message/邮件等）自行抓取 URL 生成应用名/图标卡片预览，
/// 比 SwiftUI `ShareLink(item: URL)` 更可控（后者会触发 App Store 通用 OG 模板 "Today - App Store"）。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    init(items: [Any]) {
        self.items = items
    }

    /// 便捷初始化：分享纯文本
    init(text: String) {
        self.items = [text]
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
