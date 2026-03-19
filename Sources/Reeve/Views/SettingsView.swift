import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject var configService: ConfigService

    public init() {}

    public var body: some View {
        Form {
            Section("Display") {
                Toggle("Show repo info", isOn: Binding(
                    get: { configService.config.showRepoName },
                    set: { configService.config.showRepoName = $0; configService.save() }
                ))

                Toggle("Show workspace name", isOn: Binding(
                    get: { configService.config.showWorkspaceName },
                    set: { configService.config.showWorkspaceName = $0; configService.save() }
                ))
                .disabled(!configService.config.showRepoName)
                .padding(.leading, 10)

                Toggle("Strip username prefix", isOn: Binding(
                    get: { configService.config.stripBranchPrefix },
                    set: { configService.config.stripBranchPrefix = $0; configService.save() }
                ))
                .disabled(!configService.config.showRepoName || configService.config.stripTicketPrefix)
                .padding(.leading, 10)

                Toggle("Strip ticket prefix", isOn: Binding(
                    get: { configService.config.stripTicketPrefix },
                    set: { newValue in
                        configService.config.stripTicketPrefix = newValue
                        if newValue {
                            configService.config.stripBranchPrefix = true
                        }
                        configService.save()
                    }
                ))
                .disabled(!configService.config.showRepoName)
                .padding(.leading, 10)

                Toggle("Show count in menu bar", isOn: Binding(
                    get: { configService.config.showMenuBarCount },
                    set: { configService.config.showMenuBarCount = $0; configService.save() }
                ))
            }
            Section("Panel") {
                HStack {
                    Text("Width")
                    Slider(
                        value: Binding(
                            get: { configService.config.panelWidth },
                            set: { configService.config.panelWidth = (round($0 / 20) * 20); configService.save() }
                        ),
                        in: 440...700
                    ) {
                        EmptyView()
                    } minimumValueLabel: {
                        EmptyView()
                    } maximumValueLabel: {
                        EmptyView()
                    }
                    Text("\(Int(configService.config.panelWidth))pt")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 45, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 300)
        .fixedSize()
        .navigationTitle("reeve settings")
    }
}
