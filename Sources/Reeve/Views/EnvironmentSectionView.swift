import SwiftUI

struct EnvironmentSectionView: View {
    let environment: PM2Environment
    let processes: [PM2Process]
    @EnvironmentObject var configService: ConfigService
    @EnvironmentObject var pm2Service: PM2Service

    @State private var isExpanded = true
    @State private var showCrashPopover = false
    @State private var copied = false

    private var crashLoopingProcesses: [PM2Process] {
        processes.filter(\.isCrashLooping)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if processes.isEmpty {
                Text("No processes")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(6)
            } else {
                VStack(spacing: 2) {
                    ForEach(processes) { process in
                        ProcessRowView(process: process, environment: environment)
                        if process.id != processes.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } label: {
            HStack(alignment: .center) {
                HStack(alignment: .center) {
                    Text(environment.name)
                        .font(.system(size: 13, weight: .semibold))

                    if !environment.isActive {
                        Text("offline")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(3)
                    }

                    Spacer()

                    if !crashLoopingProcesses.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                            .overlay {
                                Color.clear
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        let prompt = headerCrashLoopPrompt()
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(prompt, forType: .string)
                                        copied = true
                                    }
                                    .onHover { hovering in
                                        showCrashPopover = hovering
                                        if hovering { copied = false }
                                    }
                            }
                            .popover(isPresented: $showCrashPopover, attachmentAnchor: .point(.bottom), arrowEdge: .bottom) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 4) {
                                        Image(systemName: copied ? "checkmark" : "exclamationmark.triangle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(copied ? .green : .orange)
                                        Text(copied ? "Copied" : "\(crashLoopingProcesses.count) crash-looping")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    if !copied {
                                        ForEach(crashLoopingProcesses) { process in
                                            Text("• \(process.name) (\(process.restartCount) restarts)")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        Text("Click to copy debug prompt")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(10)
                                .interactiveDismissDisabled()
                            }
                    }

                    if let oldest = processes.map(\.createdAt).filter({ $0 > 0 }).min() {
                        Text(formattedElapsed(since: oldest))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    let onlineCount = processes.filter(\.isOnline).count
                    Text("\(onlineCount)/\(processes.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

                if environment.isActive {
                    Button {
                        Task { await pm2Service.killDaemon(environment: environment) }
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Kill PM2 daemon")
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
            }
            .padding(.trailing, -4)
        }
        .onAppear {
            isExpanded = !configService.isCollapsed(environment.path)
        }
        .onChange(of: isExpanded) { newValue in
            if newValue {
                configService.config.collapsedEnvironments.remove(environment.path)
            } else {
                configService.config.collapsedEnvironments.insert(environment.path)
            }
            configService.save()
        }
    }

    private func formattedElapsed(since timestamp: Int64) -> String {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let elapsed = max(0, now - timestamp)
        let seconds = elapsed / 1000
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24

        if days > 0 { return "\(days)d" }
        if hours > 0 { return "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    private func headerCrashLoopPrompt() -> String {
        let pm2Home = environment.path
        let envFlag = "PM2_HOME=\(pm2Home)"
        let items = crashLoopingProcesses.map { process -> String in
            let elapsedMinutes: Int = {
                guard process.createdAt > 0 else { return 0 }
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                return max(1, Int((now - process.createdAt) / 60_000))
            }()
            return "- \"\(process.name)\" has crashed \(process.restartCount) times in \(elapsedMinutes) minute\(elapsedMinutes == 1 ? "" : "s") (current uptime: \(process.formattedUptime))"
        }.joined(separator: "\n")

        return """
        The following PM2 processes in workspace "\(environment.name)" are crash-looping:

        \(items)

        To investigate, check the error logs:
        \(crashLoopingProcesses.map { "\(envFlag) pm2 logs \($0.name) --lines 100 --err" }.joined(separator: "\n"))

        Please diagnose why these processes keep crashing and fix the issues.
        """
    }
}
