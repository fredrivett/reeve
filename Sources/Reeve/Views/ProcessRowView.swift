import SwiftUI

struct ProcessRowView: View {
    let process: PM2Process
    let environment: PM2Environment
    @EnvironmentObject var pm2Service: PM2Service

    @State private var showLogs = false
    @State private var isActing = false
    @State private var showCrashPopover = false
    @State private var copied = false
    /// The port awaiting a confirm click, or nil when not confirming. Keyed to
    /// the port (not a Bool) so a poll that changes `portConflict` mid-confirm
    /// can't let a stale confirmation authorize killing a different port's holder.
    @State private var confirmingFreePort: Int?
    @State private var freePortResetTask: Task<Void, Never>?

    private static let tooltipFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                StatusBadgeView(status: process.status)
                    .frame(width: Layout.indicatorColumnWidth)

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
                    ProcessPortsView(ports: process.ports)
                    HStack(spacing: 2) {
                        if let samples = pm2Service.metricsHistory.history["\(environment.path):\(process.pmId)"], samples.count > 1 {
                            SparklineView(values: samples.map(\.cpu), color: .blue)
                        } else {
                            Color.clear.frame(width: 30, height: 12)
                        }
                        PaddedStatText(value: process.cpuPercent, suffix: "%", totalDigits: 3)
                    }
                    HStack(spacing: 2) {
                        if let samples = pm2Service.metricsHistory.history["\(environment.path):\(process.pmId)"], samples.count > 1 {
                            SparklineView(values: samples.map(\.memoryMB), color: .purple)
                        } else {
                            Color.clear.frame(width: 30, height: 12)
                        }
                        PaddedStatText(value: process.memoryMB, suffix: "MB", totalDigits: 3)
                    }
                    PaddedUptimeText(uptime: process.formattedLastActivity, totalDigits: 2)
                        .hoverTooltip(process.lastLogModified.map { "Updated: \(Self.tooltipFormatter.string(from: $0))" } ?? "Updated: –")
                    PaddedUptimeText(uptime: process.formattedUptime, totalDigits: 2)
                        .hoverTooltip(process.uptime > 0 ? "Created: \(Self.tooltipFormatter.string(from: Date(timeIntervalSince1970: Double(process.uptime) / 1000)))" : "Created: –")
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

            if let port = process.portConflict {
                portConflictBanner(port: port)
            }

            if showLogs {
                LogPanelView(process: process, environment: environment)
            }
        }
        .padding(.vertical, 3)
    }

    /// Shown when a process is failing to bind its port because something else
    /// holds it. Offers a confirm-then-kill action to free the port.
    @ViewBuilder
    private func portConflictBanner(port: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                Text("Port :\(String(port)) already in use")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.8))
            }
            Text("Another process is holding this port.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            let isConfirming = confirmingFreePort == port
            Button {
                if isConfirming {
                    confirmingFreePort = nil
                    freePortResetTask?.cancel()
                    performAction {
                        await pm2Service.freePort(port)
                        await pm2Service.restart(process: process, environment: environment)
                    }
                } else {
                    confirmingFreePort = port
                    freePortResetTask?.cancel()
                    freePortResetTask = Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if !Task.isCancelled {
                            await MainActor.run { confirmingFreePort = nil }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8))
                    Text(isConfirming ? "Confirm free port :\(String(port)) and restart service?" : "Free port :\(String(port)) and restart service")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .foregroundColor(.orange)
            .disabled(isActing)
            .help(isConfirming ? "Click again to confirm" : "Kill whatever is listening on :\(String(port)), then restart this process")
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
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
