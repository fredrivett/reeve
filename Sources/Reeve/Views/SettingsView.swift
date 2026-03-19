import SwiftUI

private struct SettingsLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .foregroundColor(.secondary.opacity(0.7))
                .frame(width: 16)
            configuration.title
        }
    }
}

public struct SettingsView: View {
    @EnvironmentObject var configService: ConfigService

    public init() {}

    public var body: some View {
        Form {
            Section("Display") {
                Toggle(isOn: Binding(
                    get: { configService.config.showRepoName },
                    set: { configService.config.showRepoName = $0; configService.save() }
                )) {
                    Label("Show repo info", systemImage: "arrow.triangle.branch")
                }

                Toggle(isOn: Binding(
                    get: { configService.config.showWorkspaceName },
                    set: { configService.config.showWorkspaceName = $0; configService.save() }
                )) {
                    Label("Show workspace name", systemImage: "folder")
                }
                .disabled(!configService.config.showRepoName)
                .padding(.leading, 10)

                Toggle(isOn: Binding(
                    get: { configService.config.stripBranchPrefix },
                    set: { configService.config.stripBranchPrefix = $0; configService.save() }
                )) {
                    Label("Strip username prefix", systemImage: "person.crop.circle.badge.minus")
                }
                .disabled(!configService.config.showRepoName || configService.config.stripTicketPrefix)
                .padding(.leading, 10)

                Toggle(isOn: Binding(
                    get: { configService.config.stripTicketPrefix },
                    set: { newValue in
                        configService.config.stripTicketPrefix = newValue
                        if newValue {
                            configService.config.stripBranchPrefix = true
                        }
                        configService.save()
                    }
                )) {
                    Label("Strip ticket prefix", systemImage: "ticket")
                }
                .disabled(!configService.config.showRepoName)
                .padding(.leading, 10)

                Toggle(isOn: Binding(
                    get: { configService.config.showMenuBarCount },
                    set: { configService.config.showMenuBarCount = $0; configService.save() }
                )) {
                    Label("Show count in menu bar", systemImage: "number")
                }

                Toggle(isOn: Binding(
                    get: { configService.config.showInactive },
                    set: { configService.config.showInactive = $0; configService.save() }
                )) {
                    Label("Show inactive environments", systemImage: "eye")
                }
            }
            Section("Panel") {
                HStack {
                    Label("Width", systemImage: "arrow.left.and.right")
                        .frame(width: 100, alignment: .leading)
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
                        .frame(width: 52, alignment: .trailing)
                }
                HStack {
                    Label("Max height", systemImage: "arrow.up.and.down")
                        .frame(width: 100, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { configService.config.panelMaxHeight },
                            set: { configService.config.panelMaxHeight = (round($0 / 20) * 20); configService.save() }
                        ),
                        in: 400...1200
                    ) {
                        EmptyView()
                    } minimumValueLabel: {
                        EmptyView()
                    } maximumValueLabel: {
                        EmptyView()
                    }
                    Text("\(Int(configService.config.panelMaxHeight))pt")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
        .labelStyle(SettingsLabelStyle())
        .formStyle(.grouped)
        .frame(width: 360)
        .fixedSize()
        .navigationTitle("reeve settings")
    }
}
