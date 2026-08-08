import SwiftUI
import UIKit

/// 系统分享面板包装：用于上下文菜单等无法直接放置 `ShareLink` 的场景。
/// 转换器工具栏、设置页等内联位置优先使用 `ShareLink`，无需本组件。
struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
