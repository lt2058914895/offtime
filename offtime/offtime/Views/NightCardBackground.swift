import SwiftUI

struct NightCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private let midnightBlue = Color(red: 0.18, green: 0.30, blue: 0.52)

    var body: some View {
        let intensity = colorScheme == .dark ? 0.50 : 0.20
        midnightBlue.opacity(intensity)
    }
}
