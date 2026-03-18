import ServiceManagement
import SwiftUI

public struct ContentView: View {
    @EnvironmentObject var pm2Service: PM2Service
    @EnvironmentObject var configService: ConfigService
    @State private var filterText = ""
    @FocusState private var filterFocused: Bool
    @State private var inactiveExpanded = false
    @State private var shimmerInactive = false

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Launch at login error: \(error)")
                }
            }
        )
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("reeve")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    ZStack(alignment: .leading) {
                        if filterText.isEmpty {
                            Text("Filter...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.6))
                                .allowsHitTesting(false)
                        }
                        TextField("", text: $filterText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .focused($filterFocused)
                            .onExitCommand { filterFocused = false }
                    }
                    .frame(width: 80)
                    .padding(.trailing, 18)
                }
                .padding(.leading, 6)
                .padding(.trailing, 2)
                .frame(height: 22)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(5)
                .overlay(alignment: .trailing) {
                    if !filterText.isEmpty {
                        Button {
                            filterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .padding(.trailing, 4)
                    }
                }

                let allCollapsed = pm2Service.environments.filter(\.isActive).allSatisfy { configService.isCollapsed($0.path) } && !inactiveExpanded

                Button {
                    let activeEnvs = pm2Service.environments.filter(\.isActive)
                    if allCollapsed {
                        for env in activeEnvs {
                            configService.config.collapsedEnvironments.remove(env.path)
                        }
                        inactiveExpanded = true
                    } else {
                        for env in activeEnvs {
                            configService.config.collapsedEnvironments.insert(env.path)
                        }
                        configService.config.expandedInactiveEnvironments.removeAll()
                        inactiveExpanded = false
                    }
                    configService.save()
                } label: {
                    Image(systemName: allCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help(allCollapsed ? "Expand all" : "Collapse all")
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }

                Button {
                    Task { await pm2Service.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }

                Menu {
                    Toggle("Launch at Login", isOn: launchAtLoginBinding)
                    Divider()
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 16)
                .opacity(0.6)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Error banner
            if let error = pm2Service.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 11))
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.yellow.opacity(0.1))

                Divider()
            }

            // Process list
            if !pm2Service.hasCompletedFirstScan {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let nameWidths: [CGFloat] = [90, 120, 70]
                    ForEach(0..<3, id: \.self) { index in
                        SkeletonRowView(nameWidth: nameWidths[index])
                        Divider().padding(.horizontal, 8)
                    }
                    // Inactive group skeleton
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.primary.opacity(0.15))
                            .frame(width: Layout.indicatorColumnWidth)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 42, height: 10)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 18, height: 10)
                        Spacer()
                    }
                    .padding(.leading, Layout.sectionLeadingPadding)
                    .padding(.trailing, Layout.sectionTrailingPadding)
                    .padding(.vertical, 9)
                    .opacity(shimmerInactive ? 0.6 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: shimmerInactive)
                    .onAppear { shimmerInactive = true }
                }
            } else if pm2Service.environments.isEmpty && pm2Service.error == nil {
                VStack(spacing: 8) {
                    Text("No PM2 environments found")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Looking for ~/.pm2 and ~/.pm2-* directories")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let activeEnvs = pm2Service.environments.filter(\.isActive)
                        let inactiveEnvs = pm2Service.environments.filter { !$0.isActive }
                        let visibleActiveEnvs = filterText.isEmpty ? activeEnvs : activeEnvs.filter { env in
                            envNameMatches(env) || !filteredProcesses(for: env.path).isEmpty
                        }

                        if !filterText.isEmpty && visibleActiveEnvs.isEmpty {
                            Text("No matching processes")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        }

                        ForEach(visibleActiveEnvs) { env in
                            EnvironmentSectionView(
                                environment: env,
                                processes: envNameMatches(env) ? (pm2Service.processesByEnvironment[env.path] ?? []) : filteredProcesses(for: env.path),
                                forceExpanded: !filterText.isEmpty
                            )
                            .padding(.leading, Layout.sectionLeadingPadding)
                            .padding(.trailing, Layout.sectionTrailingPadding)
                            .padding(.vertical, 8)

                            if env.id != visibleActiveEnvs.last?.id || (filterText.isEmpty && !inactiveEnvs.isEmpty) {
                                Divider().padding(.horizontal, 8)
                            }
                        }

                        if !inactiveEnvs.isEmpty && filterText.isEmpty {
                            DisclosureGroup(isExpanded: $inactiveExpanded) {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(inactiveEnvs) { env in
                                        EnvironmentSectionView(
                                            environment: env,
                                            processes: []
                                        )
                                        .padding(.leading, 16)
                                        .padding(.trailing, Layout.sectionTrailingPadding)
                                        .padding(.vertical, 2)
                                    }
                                }
                                .overlay(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.3))
                                        .frame(width: 1.5)
                                        .padding(.leading, 2)
                                }
                                .padding(.bottom, 8)
                            } label: {
                                HStack {
                                    Text("Inactive (\(inactiveEnvs.count))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .onTapGesture { inactiveExpanded.toggle() }
                                        .onHover { hovering in
                                            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                        }

                                    if inactiveExpanded {
                                        ConfirmableButton(
                                            icon: "trash",
                                            confirmText: "Clear all?",
                                            help: "Remove all inactive PM2 directories"
                                        ) {
                                            pm2Service.clearInactiveEnvironments()
                                        }
                                    }
                                }
                            }
                            .disclosureGroupStyle(AlignedDisclosureGroupStyle())
                            .padding(.leading, Layout.sectionLeadingPadding)
                            .padding(.trailing, Layout.sectionTrailingPadding)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }

        }
        .padding(.bottom, 4)
        .frame(width: 460)
        .frame(maxHeight: 800)
        .clampToScreen()
    }

    private func envNameMatches(_ env: PM2Environment) -> Bool {
        guard !filterText.isEmpty else { return false }
        return env.name.lowercased().contains(filterText.lowercased())
    }

    private func filteredProcesses(for environmentPath: String) -> [PM2Process] {
        let processes = pm2Service.processesByEnvironment[environmentPath] ?? []
        guard !filterText.isEmpty else { return processes }
        let query = filterText.lowercased()
        return processes.filter { process in
            process.name.lowercased().contains(query) ||
            (process.port.map { String($0).contains(query) } ?? false)
        }
    }
}
