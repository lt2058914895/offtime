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

/// iPad 内容宽度限制修饰器
struct ReadableContentModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
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