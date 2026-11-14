import AppKit

/// reeve's menu bar glyph: a reeve's crook with a lantern that shows health.
/// Same 24 pt grid as `assets/AppIcon.svg`.
///
/// Not a template image: macOS would flatten the lantern's colour into the
/// menu bar tint. The colours resolve when the image draws, so `labelColor`
/// follows the menu bar's appearance rather than the app's; that's also why
/// the lantern's colour is picked inside the drawing handler.
public enum MenuBarIcon {
    public static func image(for health: ProcessHealth) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let lamp: NSColor = switch health {
            case .scanning: .labelColor.withAlphaComponent(0.3)
            case .healthy: .labelColor
            case .warning: .systemOrange
            case .failing: .systemRed
            }
            let grid = NSAffineTransform()
            grid.scale(by: rect.width / 24)
            grid.concat()

            NSColor.labelColor.setStroke()
            let crook = NSBezierPath()
            crook.lineWidth = 1.8
            crook.lineCapStyle = .round
            crook.lineJoinStyle = .round
            crook.move(to: NSPoint(x: 8, y: 21))
            crook.line(to: NSPoint(x: 8, y: 9))
            crook.appendArc(withCenter: NSPoint(x: 12.5, y: 9), radius: 4.5, startAngle: 180, endAngle: 0, clockwise: false)
            crook.line(to: NSPoint(x: 17, y: 9.6))
            crook.move(to: NSPoint(x: 5.5, y: 21))
            crook.line(to: NSPoint(x: 10.5, y: 21))
            crook.move(to: NSPoint(x: 15, y: 13.5))
            crook.line(to: NSPoint(x: 19, y: 13.5))
            crook.stroke()

            let hanger = NSBezierPath()
            hanger.lineWidth = 1
            hanger.move(to: NSPoint(x: 17, y: 9.6))
            hanger.line(to: NSPoint(x: 17, y: 12.9))
            hanger.stroke()

            lamp.setFill()
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 15.3, y: 14.5))
            body.line(to: NSPoint(x: 18.7, y: 14.5))
            body.line(to: NSPoint(x: 18.7, y: 17.1))
            body.appendArc(withCenter: NSPoint(x: 17, y: 17.1), radius: 1.7, startAngle: 0, endAngle: 180, clockwise: false)
            body.close()
            body.fill()
            return true
        }
        image.accessibilityDescription = switch health {
        case .scanning: "reeve, scanning"
        case .healthy: "reeve"
        case .warning: "reeve, a process is restarting"
        case .failing: "reeve, a process has errored"
        }
        return image
    }
}
