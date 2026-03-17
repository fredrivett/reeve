import SwiftUI

struct LogPanelView: View {
    let process: PM2Process
    let environment: PM2Environment
    @EnvironmentObject var pm2Service: PM2Service

    @State private var logLines: [String] = []
    @State private var streamProcess: Foundation.Process?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(logLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(height: 150)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .cornerRadius(4)
            .onChange(of: logLines.count) { _ in
                if let last = logLines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
        .onAppear { startStreaming() }
        .onDisappear { stopStreaming() }
    }

    private func startStreaming() {
        streamProcess = pm2Service.startLogStream(
            process: process,
            environment: environment
        ) { text in
            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            DispatchQueue.main.async {
                logLines.append(contentsOf: lines)
                // Cap buffer at 500 lines
                if logLines.count > 500 {
                    logLines.removeFirst(logLines.count - 500)
                }
            }
        }
    }

    private func stopStreaming() {
        pm2Service.stopLogStream(streamProcess)
        streamProcess = nil
    }
}
