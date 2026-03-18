import SwiftUI

struct ProcessRowView: View {
    let process: PM2Process
    let environment: PM2Environment
    @EnvironmentObject var pm2Service: PM2Service

    @State private var showLogs = false
    @State private var isActing = false
    @State private var showCrashPopover = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                StatusBadgeView(status: process.status)

                Text(process.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .onTapGesture { showLogs.toggle() }
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }

                Spacer()

                if process.isCrashLooping {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .overlay {
                            // Invisible larger hit target
                            Color.clear
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    let prompt = crashLoopPrompt(process: process, environment: environment)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(prompt, forType: .string)
                                    copied = true
                                }
                                .onHover { hovering in
                                    showCrashPopover = hovering
                                    if hovering {
                                        copied = false
                                    }
                                }
                        }
                        .popover(isPresented: $showCrashPopover, attachmentAnchor: .point(.bottom), arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 4) {
                                    Image(systemName: copied ? "checkmark" : "exclamationmark.triangle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(copied ? .green : .orange)
                                    Text(copied ? "Copied" : "Crash-looping")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                if !copied {
                                    Text("\(process.restartCount) restarts, \(process.formattedUptime) uptime")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Text("Click to copy debug prompt")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(10)
                            .interactiveDismissDisabled()
                            .onHover { hovering in
                                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                            }
                        }
                }

                // Stats
                if process.isOnline {
                    if let port = process.port {
                        Text(":\(String(port))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 2) {
                        if let samples = pm2Service.metricsHistory.history["\(environment.path):\(process.pmId)"], samples.count > 1 {
                            SparklineView(values: samples.map(\.cpu), color: .blue)
                        }
                        Text(process.formattedCPU)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 2) {
                        if let samples = pm2Service.metricsHistory.history["\(environment.path):\(process.pmId)"], samples.count > 1 {
                            SparklineView(values: samples.map(\.memoryMB), color: .purple)
                        }
                        Text(process.formattedMemory)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
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
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }

                    if process.isOnline {
                        ConfirmableButton(
                            icon: "stop.fill",
                            confirmText: "Stop?",
                            help: "Stop"
                        ) {
                            performAction { await pm2Service.stop(process: process, environment: environment) }
                        }
                    }

                    ConfirmableButton(
                        icon: "trash",
                        confirmText: "Delete?",
                        help: "Delete",
                        confirmColor: .red
                    ) {
                        performAction { await pm2Service.delete(process: process, environment: environment) }
                    }
                }
                .disabled(isActing)
            }

            if showLogs {
                LogPanelView(process: process, environment: environment)
            }
        }
        .padding(.vertical, 1)
    }

    private func crashLoopPrompt(process: PM2Process, environment: PM2Environment) -> String {
        let pm2Home = environment.path
        let envFlag = "PM2_HOME=\(pm2Home)"
        let elapsedMinutes: Int = {
            guard process.createdAt > 0 else { return 0 }
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            return max(1, Int((now - process.createdAt) / 60_000))
        }()
        return """
        The PM2 process "\(process.name)" in workspace "\(environment.name)" is crash-looping. \
        It has crashed \(process.restartCount) times in \(elapsedMinutes) minute\(elapsedMinutes == 1 ? "" : "s") and currently has only \(process.formattedUptime) of uptime.

        To investigate, check the error logs:
        \(envFlag) pm2 logs \(process.name) --lines 100 --err

        Or check full logs:
        \(envFlag) pm2 logs \(process.name) --lines 100

        Please diagnose why this process keeps crashing and fix the issue.
        """
    }

    private func performAction(_ action: @escaping () async -> Void) {
        isActing = true
        Task {
            await action()
            isActing = false
        }
    }
}
