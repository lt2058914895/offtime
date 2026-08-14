import UIKit

/// 轻量触觉反馈封装：按操作语义调用对应风格，无需手动管理 generator 生命周期。
enum Haptics {
    /// 选择切换（勾选/取消勾选城市）
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// 轻量冲击（拖拽排序落位）
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 中量冲击（删除城市、交换城市）
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// 成功通知（添加城市、导入成功）
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 警告通知（城市已存在）
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// 错误通知（添加/删除/导入失败）
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
