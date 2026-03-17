import SwiftUI

struct StatusBadgeView: View {
    let status: String

    private var color: Color {
        switch status {
        case "online": return .green
        case "launching", "stopping": return .yellow
        case "errored": return .red
        case "stopped": return .gray
        default: return .gray
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}
