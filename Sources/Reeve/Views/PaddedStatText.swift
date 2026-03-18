import SwiftUI

/// Displays a numeric stat with leading zeros faded out for visual alignment.
/// e.g. value=9, suffix="MB", totalDigits=3 → "009MB" with "00" at 50% opacity.
struct PaddedStatText: View {
    let value: Double
    let suffix: String
    let totalDigits: Int

    var body: some View {
        let intValue = Int(value.rounded(.down))
        let digits = String(intValue)
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
}
