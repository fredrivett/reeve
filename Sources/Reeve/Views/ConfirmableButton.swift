import SwiftUI

/// A button that requires a second click to confirm. First click shows confirmation text,
/// second click executes the action. Resets after a timeout or when the view loses hover.
struct ConfirmableButton: View {
    let icon: String
    let confirmText: String
    let help: String
    var confirmColor: Color = .red
    let action: () -> Void

    @State private var confirming = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            if confirming {
                confirming = false
                resetTask?.cancel()
                action()
            } else {
                confirming = true
                resetTask?.cancel()
                resetTask = Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if !Task.isCancelled {
                        await MainActor.run { confirming = false }
                    }
                }
            }
        } label: {
            if confirming {
                Text(confirmText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(confirmColor)
                    .cornerRadius(4)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 10))
            }
        }
        .buttonStyle(.borderless)
        .help(confirming ? "Click again to confirm" : help)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
