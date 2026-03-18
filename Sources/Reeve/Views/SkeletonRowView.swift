import SwiftUI

struct SkeletonRowView: View {
    let nameWidth: CGFloat
    @State private var shimmer = false

    var body: some View {
        HStack(spacing: 6) {
            // Arrow matching DisclosureGroup
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(.primary.opacity(0.15))

            // Name
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.12))
                .frame(width: nameWidth, height: 13)

            Spacer()

            // Port (:5500X)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 42, height: 10)

            // CPU%
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 20, height: 10)

            // Memory
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 32, height: 10)

            // Uptime
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 22, height: 10)

            // Count (e.g. 5/5)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 22, height: 10)

            // Power button placeholder
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 14, height: 14)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .opacity(shimmer ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: shimmer)
        .onAppear { shimmer = true }
    }
}
