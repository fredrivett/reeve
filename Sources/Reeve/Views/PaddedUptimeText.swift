import SwiftUI

/// Displays an uptime string (e.g. "5h", "30m") with leading zeros faded out for visual alignment.
/// e.g. "5h" with totalDigits=2 → "05h" with "0" at 50% opacity.
struct PaddedUptimeText: View {
    let uptime: String
    let totalDigits: Int

    var body: some View {
        let (digits, suffix) = splitUptime(uptime)
        let padCount = max(0, totalDigits - digits.count)
        let padding = String(repeating: "0", count: padCount)

        HStack(spacing: 0) {
            if padCount > 0 {
                Text(padding)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            Text(digits + suffix)
                .foregroundColor(.secondary)
        }
        .font(.system(size: 10, design: .monospaced))
    }

    private func splitUptime(_ value: String) -> (digits: String, suffix: String) {
        let digits = value.prefix(while: { $0.isNumber })
        let suffix = value.dropFirst(digits.count)
        return (String(digits), String(suffix))
    }
}
