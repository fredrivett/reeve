import SwiftUI

struct EnvironmentSectionView: View {
    let environment: PM2Environment
    let processes: [PM2Process]
    @EnvironmentObject var configService: ConfigService
    @EnvironmentObject var pm2Service: PM2Service

    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if processes.isEmpty {
                Text("No processes")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(processes) { process in
                    ProcessRowView(process: process, environment: environment)
                    if process.id != processes.last?.id {
                        Divider()
                    }
                }
            }
        } label: {
            HStack {
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

                let onlineCount = processes.filter(\.isOnline).count
                Text("\(onlineCount)/\(processes.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                if environment.isActive {
                    Button {
                        Task { await pm2Service.killDaemon(environment: environment) }
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Kill PM2 daemon")
                }
            }
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
}
