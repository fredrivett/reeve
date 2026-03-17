import SwiftUI

struct ProcessRowView: View {
    let process: PM2Process
    let environment: PM2Environment
    @EnvironmentObject var pm2Service: PM2Service

    @State private var showLogs = false
    @State private var isActing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                StatusBadgeView(status: process.status)

                Text(process.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer()

                // Stats
                if process.isOnline {
                    Text(process.formattedCPU)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(process.formattedMemory)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(process.formattedUptime)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Controls
                HStack(spacing: 4) {
                    Button {
                        performAction { await pm2Service.restart(process: process, environment: environment) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Restart")

                    if process.isOnline {
                        Button {
                            performAction { await pm2Service.stop(process: process, environment: environment) }
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .help("Stop")
                    }

                    Button {
                        performAction { await pm2Service.delete(process: process, environment: environment) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")

                    Button {
                        showLogs.toggle()
                    } label: {
                        Image(systemName: showLogs ? "text.below.photo.fill" : "text.below.photo")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Logs")
                }
                .disabled(isActing)
            }

            if showLogs {
                LogPanelView(process: process, environment: environment)
            }
        }
        .padding(.vertical, 2)
    }

    private func performAction(_ action: @escaping () async -> Void) {
        isActing = true
        Task {
            await action()
            isActing = false
        }
    }
}
