import SwiftUI

/// 行程：占位空页面，后续迭代填充内容。
struct TripView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ContentUnavailableView(
            String(localized: "trip.empty.title"),
            systemImage: "airplane",
            description: Text(String(localized: "trip.empty"))
        )
        .navigationTitle(String(localized: "tab.travel"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}

#Preview {
    NavigationStack {
        TripView()
    }
}
