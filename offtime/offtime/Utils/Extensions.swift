import SwiftUI

extension View {
    func toast(message: Binding<String?>) -> some View {
        self.modifier(ToastModifier(message: message))
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

extension String {
    /// 计算与目标字符串的编辑距离（Levenshtein Distance），用于模糊匹配
    func levenshteinDistance(to target: String) -> Int {
        let len1 = count
        let len2 = target.count

        var matrix = Array(repeating: Array(repeating: 0, count: len2 + 1), count: len1 + 1)

        for i in 0...len1 { matrix[i][0] = i }
        for j in 0...len2 { matrix[0][j] = j }

        let arr1 = Array(self)
        let arr2 = Array(target)

        for i in 1...len1 {
            for j in 1...len2 {
                let cost = arr1[i - 1] == arr2[j - 1] ? 0 : 1
                matrix[i][j] = Swift.min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }

        return matrix[len1][len2]
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
            .onChange(of: message) { _, newValue in
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