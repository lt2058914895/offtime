import SwiftUI

extension View {
    func toast(message: Binding<String?>) -> some View {
        self.modifier(ToastModifier(message: message))
    }
}

struct ToastModifier: ViewModifier {
    @Binding var message: String?
    
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
                if newValue != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        message = nil
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
