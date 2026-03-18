import SwiftUI

struct SparklineView: View {
    let values: [Double]
    let color: Color
    var width: CGFloat = 30
    var height: CGFloat = 12

    var body: some View {
        let normalized = MetricsHistory.normalize(values)
        Canvas { context, size in
            guard normalized.count > 1 else { return }
            let stepX = size.width / CGFloat(normalized.count - 1)
            var path = Path()
            for (i, value) in normalized.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height * (1.0 - CGFloat(value))
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
        .frame(width: width, height: height)
    }
}
