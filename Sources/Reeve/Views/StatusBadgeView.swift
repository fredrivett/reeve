import SwiftUI

struct StatusBadgeView: View {
    let status: String

    private var color: Color {
        switch status {
        case "online": return .green
        case "errored": return .red
        default: return .gray
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}
