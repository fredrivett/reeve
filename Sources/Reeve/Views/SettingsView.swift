import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject var configService: ConfigService

    public init() {}

    public var body: some View {
        Form {
            Toggle("Show repo info", isOn: Binding(
                get: { configService.config.showRepoName },
                set: { configService.config.showRepoName = $0; configService.save() }
            ))

            Toggle("Strip username prefix", isOn: Binding(
                get: { configService.config.stripBranchPrefix },
                set: { configService.config.stripBranchPrefix = $0; configService.save() }
            ))
            .disabled(!configService.config.showRepoName || configService.config.stripTicketPrefix)

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
        }
        .formStyle(.grouped)
        .frame(width: 300)
        .fixedSize()
        .navigationTitle("reeve settings")
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
