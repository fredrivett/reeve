import SwiftUI

enum Layout {
    static let sectionLeadingPadding: CGFloat = 12
    static let sectionTrailingPadding: CGFloat = 12
    /// Fixed width for the leading indicator column (disclosure arrow / status dot)
    static let indicatorColumnWidth: CGFloat = 12
}

struct AlignedDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(configuration.isExpanded ? .degrees(90) : .zero)
                        .animation(.easeInOut(duration: 0.15), value: configuration.isExpanded)
                        .frame(width: Layout.indicatorColumnWidth)
                    configuration.label
                }
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
                    .padding(.top, 4)
                    .padding(.bottom, 2)
            }
        }
    }
}
