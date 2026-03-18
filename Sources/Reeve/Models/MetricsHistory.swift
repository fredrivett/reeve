import Foundation

@MainActor
public class MetricsHistory: ObservableObject {
    public struct MetricSample {
        public let cpu: Double
        public let memoryMB: Double
        public let timestamp: Date
    }

    // Key: "\(environmentPath):\(pm_id)"
    @Published public var history: [String: [MetricSample]] = [:]

    private let maxSamples = 20

    public init() {}

    public func record(process: PM2Process, environmentPath: String) {
        let key = "\(environmentPath):\(process.pmId)"
        appendSample(key: key, cpu: process.cpuPercent, memoryMB: process.memoryMB)
    }

    public func recordEnvironment(path: String, processes: [PM2Process]) {
        let online = processes.filter(\.isOnline)
        let totalCPU = online.reduce(0.0) { $0 + $1.cpuPercent }
        let totalMemMB = online.reduce(0.0) { $0 + $1.memoryMB }
        appendSample(key: "env:\(path)", cpu: totalCPU, memoryMB: totalMemMB)
    }

    private func appendSample(key: String, cpu: Double, memoryMB: Double) {
        var samples = history[key, default: []]
        samples.append(MetricSample(cpu: cpu, memoryMB: memoryMB, timestamp: Date()))
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        history[key] = samples
    }

    /// Normalize an array of values to 0...1 range. Single-value arrays return [0.5].
    public nonisolated static func normalize(_ values: [Double]) -> [Double] {
        guard values.count > 1 else {
            return values.isEmpty ? [] : [0.5]
        }
        let minVal = values.min()!
        let maxVal = values.max()!
        let range = maxVal - minVal
        if range == 0 {
            return values.map { _ in 0.5 }
        }
        return values.map { ($0 - minVal) / range }
    }
}
