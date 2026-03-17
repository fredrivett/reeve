import SwiftUI

struct ContentView: View {
    @EnvironmentObject var pm2Service: PM2Service
    @EnvironmentObject var configService: ConfigService

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Reeve")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Button {
                    Task { await pm2Service.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Refresh")
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
            if pm2Service.environments.isEmpty && pm2Service.error == nil {
                VStack(spacing: 8) {
                    Text("No PM2 environments found")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Looking for ~/.pm2 and ~/.pm2-* directories")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let activeEnvs = pm2Service.environments.filter(\.isActive)
                        let inactiveEnvs = pm2Service.environments.filter { !$0.isActive }

                        ForEach(activeEnvs) { env in
                            EnvironmentSectionView(
                                environment: env,
                                processes: pm2Service.processesByEnvironment[env.path] ?? []
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)

                            if env.id != activeEnvs.last?.id || !inactiveEnvs.isEmpty {
                                Divider().padding(.horizontal, 8)
                            }
                        }

                        if !inactiveEnvs.isEmpty {
                            DisclosureGroup {
                                ForEach(inactiveEnvs) { env in
                                    EnvironmentSectionView(
                                        environment: env,
                                        processes: []
                                    )
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 2)
                                }
                            } label: {
                                Text("Inactive (\(inactiveEnvs.count))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 380)
        .frame(minHeight: 200, maxHeight: 800)
    }
}
