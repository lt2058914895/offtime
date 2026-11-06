import SwiftUI
import UIKit

/// 系统分享面板包装：用于上下文菜单、设置页等需要 `UIActivityViewController` 的场景。
/// 直接把 item 交给系统，由各渠道（微信/Message/邮件等）自行抓取 URL 生成应用名/图标卡片预览，
/// 比 SwiftUI `ShareLink(item: URL)` 更可控（后者会触发 App Store 通用 OG 模板 "Today - App Store"）。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: (() -> Void)?

    init(items: [Any], onComplete: (() -> Void)? = nil) {
        self.items = items
        self.onComplete = onComplete
    }

    /// 便捷初始化：分享纯文本
    init(text: String, onComplete: (() -> Void)? = nil) {
        self.items = [text]
        self.onComplete = onComplete
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
