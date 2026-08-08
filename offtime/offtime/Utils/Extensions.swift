import SwiftUI

extension View {
    func toast(message: Binding<String?>) -> some View {
        self.modifier(ToastModifier(message: message))
    }
    
    /// iPad 适配：在 regular 横向尺寸下限制内容最大宽度并居中
    func readableContentPadding() -> some View {
        modifier(ReadableContentModifier())
    }
}

extension Locale {
    /// 系统当前是否使用 24 小时制。基于 locale 时间格式模板 "j" 推断，
    /// "j" 在 12 小时制 locale 下会展开为含 "a"（AM/PM）的格式，反之不含。
    /// 反映用户在系统设置中的"24小时制"开关。
    static var systemUses24Hour: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)
        return !(format?.contains("a") ?? true)
    }
}

/// iPad 内容宽度限制修饰器（已弃用宽度限制，各视图独立适配 iPad 布局）
struct ReadableContentModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    func body(content: Content) -> some View {
        content
    }
}

struct ToastModifier: ViewModifier {
    @Binding var message: String?
    @State private var dismissTask: Task<Void, Never>?
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if let message = message {
                        ToastView(message: message)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            )
            .onChange(of: message) { newValue in
                // 取消之前的定时任务，避免连续设置 toast 时提前消失
                dismissTask?.cancel()
                
                if newValue != nil {
                    dismissTask = Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            message = nil
                        }
                    }
                }
            }
    }
}

struct ToastView: View {
    let message: String
    
    var body: some View {
        VStack {
            Spacer()
            Text(message)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
                .shadow(radius: 4)
        }
        .padding(.bottom, 32)
        .animation(.easeInOut(duration: 0.3), value: message)
    }
}