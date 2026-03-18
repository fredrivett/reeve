import Testing
@testable import ReeveLib
import Foundation

// MARK: - Helpers

private func decode(_ json: String) throws -> PM2Process {
    let data = json.data(using: .utf8)!
    return try JSONDecoder().decode(PM2Process.self, from: data)
}

private func decodeArray(_ json: String) throws -> [PM2Process] {
    let data = json.data(using: .utf8)!
    return try JSONDecoder().decode([PM2Process].self, from: data)
}

// MARK: - PM2Process JSON Decoding

@Suite("PM2Process Decoding")
struct PM2ProcessDecodingTests {

    @Test("Decode online process with all fields")
    func decodeOnlineProcess() throws {
        let json = """
        {
            "pid": 1234,
            "name": "web-server",
            "pm_id": 0,
            "monit": { "memory": 52428800, "cpu": 12.5 },
            "pm2_env": {
                "status": "online",
                "namespace": "production",
                "pm_exec_path": "/usr/bin/node",
                "pm_cwd": "/app",
                "exec_mode": "cluster_mode",
                "pm_uptime": 1700000000000,
                "restart_time": 2,
                "created_at": 1700000000000,
                "pm_out_log_path": "/tmp/out.log",
                "pm_err_log_path": "/tmp/err.log"
            }
        }
        """
        let process = try decode(json)
        #expect(process.pid == 1234)
        #expect(process.name == "web-server")
        #expect(process.pmId == 0)
        #expect(process.memoryBytes == 52428800)
        #expect(process.cpuPercent == 12.5)
        #expect(process.status == "online")
        #expect(process.namespace == "production")
        #expect(process.execPath == "/usr/bin/node")
        #expect(process.cwd == "/app")
        #expect(process.execMode == "cluster_mode")
        #expect(process.uptime == 1700000000000)
        #expect(process.restartCount == 2)
        #expect(process.createdAt == 1700000000000)
        #expect(process.outLogPath == "/tmp/out.log")
        #expect(process.errLogPath == "/tmp/err.log")
        #expect(process.isOnline)
        #expect(!process.isStopped)
        #expect(!process.isErrored)
    }

    @Test("Decode stopped process")
    func decodeStoppedProcess() throws {
        let json = """
        {
            "pid": 0,
            "name": "worker",
            "pm_id": 1,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "stopped" }
        }
        """
        let process = try decode(json)
        #expect(process.status == "stopped")
        #expect(!process.isOnline)
        #expect(process.isStopped)
        #expect(!process.isErrored)
    }

    @Test("Decode errored process")
    func decodeErroredProcess() throws {
        let json = """
        {
            "pid": 0,
            "name": "crasher",
            "pm_id": 2,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "errored", "restart_time": 15 }
        }
        """
        let process = try decode(json)
        #expect(process.status == "errored")
        #expect(!process.isOnline)
        #expect(!process.isStopped)
        #expect(process.isErrored)
        #expect(process.restartCount == 15)
    }

    @Test("Missing optional fields use defaults")
    func missingOptionalFieldsUseDefaults() throws {
        let json = """
        {
            "pid": 99,
            "name": "minimal",
            "pm_id": 5,
            "monit": { "memory": 1000, "cpu": 0.0 },
            "pm2_env": { "status": "online" }
        }
        """
        let process = try decode(json)
        #expect(process.namespace == "default")
        #expect(process.execPath == "")
        #expect(process.cwd == "")
        #expect(process.execMode == "fork_mode")
        #expect(process.uptime == 0)
        #expect(process.restartCount == 0)
        #expect(process.createdAt == 0)
        #expect(process.outLogPath == "")
        #expect(process.errLogPath == "")
        #expect(process.port == nil)
    }

    @Test("Decode array of processes")
    func decodeArray() throws {
        let json = """
        [
            { "pid": 1, "name": "a", "pm_id": 0, "monit": { "memory": 0, "cpu": 0.0 }, "pm2_env": { "status": "online" } },
            { "pid": 2, "name": "b", "pm_id": 1, "monit": { "memory": 0, "cpu": 0.0 }, "pm2_env": { "status": "stopped" } }
        ]
        """
        let processes = try reeveTests.decodeArray(json)
        #expect(processes.count == 2)
        #expect(processes[0].name == "a")
        #expect(processes[1].name == "b")
    }

    @Test("Decode empty array")
    func decodeEmptyArray() throws {
        let processes = try reeveTests.decodeArray("[]")
        #expect(processes.isEmpty)
    }
}

// MARK: - Port Extraction

@Suite("Port Extraction")
struct PortExtractionTests {

    @Test("Port from --port arg")
    func portFromArgs() throws {
        let json = """
        {
            "pid": 1, "name": "srv", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "args": ["--port", "3000"] }
        }
        """
        #expect(try decode(json).port == 3000)
    }

    @Test("Port from -p arg")
    func portFromShortFlag() throws {
        let json = """
        {
            "pid": 1, "name": "srv", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "args": ["-p", "8080"] }
        }
        """
        #expect(try decode(json).port == 8080)
    }

    @Test("Port from GPTZERO_CUSTOM_PORT (int)")
    func portFromGPTZeroInt() throws {
        let json = """
        {
            "pid": 1, "name": "srv", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "GPTZERO_CUSTOM_PORT": 55001 }
        }
        """
        #expect(try decode(json).port == 55001)
    }

    @Test("Port from GPTZERO_CUSTOM_PORT (string)")
    func portFromGPTZeroString() throws {
        let json = """
        {
            "pid": 1, "name": "srv", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "GPTZERO_CUSTOM_PORT": "55002" }
        }
        """
        #expect(try decode(json).port == 55002)
    }

    @Test("Port from PORT env var (int)")
    func portFromPORTInt() throws {
        let json = """
        {
            "pid": 1, "name": "srv", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "PORT": 4000 }
        }
        """
        #expect(try decode(json).port == 4000)
    }

    @Test("Port from PORT env var (string)")
    func portFromPORTString() throws {
        let json = """
        {
            "pid": 1, "name": "srv", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "PORT": "4001" }
        }
        """
        #expect(try decode(json).port == 4001)
    }

    @Test("Args port takes precedence over env vars")
    func argsPrecedence() throws {
        let json = """
        {
            "pid": 1, "name": "srv", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "args": ["--port", "9000"], "PORT": 4000, "GPTZERO_CUSTOM_PORT": 5000 }
        }
        """
        #expect(try decode(json).port == 9000)
    }

    @Test("GPTZERO_CUSTOM_PORT takes precedence over PORT")
    func gptzeroPortPrecedence() throws {
        let json = """
        {
            "pid": 1, "name": "srv", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "PORT": 4000, "GPTZERO_CUSTOM_PORT": 5000 }
        }
        """
        #expect(try decode(json).port == 5000)
    }

    @Test("No port when none specified")
    func noPort() throws {
        let json = """
        {
            "pid": 1, "name": "srv", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "args": ["--verbose"] }
        }
        """
        #expect(try decode(json).port == nil)
    }
}

// MARK: - PM2Process Computed Properties

@Suite("PM2Process Computed Properties")
struct PM2ProcessComputedPropertyTests {

    @Test("ID is pm_id as string")
    func idIsPmIdString() throws {
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 42,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online" }
        }
        """
        #expect(try decode(json).id == "42")
    }

    @Test("Formatted memory in MB")
    func formattedMemoryMB() throws {
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 52428800, "cpu": 0.0 },
            "pm2_env": { "status": "online" }
        }
        """
        #expect(try decode(json).formattedMemory == "50MB")
    }

    @Test("Formatted memory in GB")
    func formattedMemoryGB() throws {
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 1610612736, "cpu": 0.0 },
            "pm2_env": { "status": "online" }
        }
        """
        #expect(try decode(json).formattedMemory == "1.5GB")
    }

    @Test("Formatted memory zero")
    func formattedMemoryZero() throws {
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "stopped" }
        }
        """
        #expect(try decode(json).formattedMemory == "0MB")
    }

    @Test("Formatted CPU rounds")
    func formattedCPU() throws {
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 45.7 },
            "pm2_env": { "status": "online" }
        }
        """
        #expect(try decode(json).formattedCPU == "46%")
    }

    @Test("Formatted CPU zero")
    func formattedCPUZero() throws {
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online" }
        }
        """
        #expect(try decode(json).formattedCPU == "0%")
    }

    @Test("Formatted uptime with zero returns dash")
    func formattedUptimeZero() throws {
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "stopped", "pm_uptime": 0 }
        }
        """
        #expect(try decode(json).formattedUptime == "\u{2013}")
    }

    @Test("Formatted uptime in seconds")
    func formattedUptimeSeconds() throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let uptimeMs = nowMs - 10_000
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "pm_uptime": \(uptimeMs) }
        }
        """
        #expect(try decode(json).formattedUptime == "10s")
    }

    @Test("Formatted uptime in minutes")
    func formattedUptimeMinutes() throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let uptimeMs = nowMs - 300_000
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "pm_uptime": \(uptimeMs) }
        }
        """
        #expect(try decode(json).formattedUptime == "5m")
    }

    @Test("Formatted uptime in hours")
    func formattedUptimeHours() throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let uptimeMs = nowMs - 7_200_000
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "pm_uptime": \(uptimeMs) }
        }
        """
        #expect(try decode(json).formattedUptime == "2h")
    }

    @Test("Formatted uptime in days")
    func formattedUptimeDays() throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let uptimeMs = nowMs - 172_800_000
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "pm_uptime": \(uptimeMs) }
        }
        """
        #expect(try decode(json).formattedUptime == "2d")
    }

    @Test("memoryMB computed correctly")
    func memoryMB() throws {
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 104857600, "cpu": 0.0 },
            "pm2_env": { "status": "online" }
        }
        """
        let process = try decode(json)
        #expect(abs(process.memoryMB - 100.0) < 0.01)
    }
}

// MARK: - Crash Looping

@Suite("Crash Looping Detection")
struct CrashLoopingTests {

    @Test("Not crash looping when stopped")
    func notCrashLoopingWhenStopped() throws {
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "stopped", "restart_time": 100, "pm_uptime": \(Int64(Date().timeIntervalSince1970 * 1000)) }
        }
        """
        let process = try decode(json)
        #expect(!process.isCrashLooping)
    }

    @Test("Not crash looping with low restart count")
    func notCrashLoopingLowRestarts() throws {
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "restart_time": 1, "pm_uptime": \(Int64(Date().timeIntervalSince1970 * 1000)) }
        }
        """
        let process = try decode(json)
        #expect(!process.isCrashLooping)
    }

    @Test("Crash looping detected")
    func crashLoopingDetected() throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "restart_time": 5, "pm_uptime": \(nowMs - 5000) }
        }
        """
        #expect(try decode(json).isCrashLooping)
    }

    @Test("Not crash looping with long uptime")
    func notCrashLoopingLongUptime() throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "restart_time": 5, "pm_uptime": \(nowMs - 120_000) }
        }
        """
        let process = try decode(json)
        #expect(!process.isCrashLooping)
    }

    @Test("Not crash looping with zero uptime")
    func notCrashLoopingZeroUptime() throws {
        let json = """
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online", "restart_time": 10, "pm_uptime": 0 }
        }
        """
        let process = try decode(json)
        #expect(!process.isCrashLooping)
    }
}

// MARK: - Port Range Formatting

@Suite("Port Range Formatting")
struct PortRangeFormattingTests {

    @Test("Empty ports returns nil")
    func emptyPorts() {
        #expect(formatPortRange(from: []) == nil)
    }

    @Test("Single port")
    func singlePort() {
        #expect(formatPortRange(from: [3000]) == ":300X")
    }

    @Test("Ports within ten range use X notation")
    func portsWithinTenRange() {
        #expect(formatPortRange(from: [55001, 55002, 55003]) == ":5500X")
    }

    @Test("Ports exactly at ten-range boundary")
    func portsAtTenBoundary() {
        #expect(formatPortRange(from: [55000, 55009]) == ":5500X")
    }

    @Test("Ports crossing ten boundary show range")
    func portsCrossingTenBoundary() {
        #expect(formatPortRange(from: [55009, 55010]) == ":55009-55010")
    }

    @Test("Wide range shows min-max")
    func wideRange() {
        #expect(formatPortRange(from: [3000, 4000]) == ":3000-4000")
    }

    @Test("Two identical ports")
    func identicalPorts() {
        #expect(formatPortRange(from: [8080, 8080]) == ":808X")
    }

    @Test("Ports in same decade")
    func portsInSameDecade() {
        #expect(formatPortRange(from: [8080, 8081, 8085]) == ":808X")
    }
}

// MARK: - ANSI Code Stripping

@Suite("ANSI Code Stripping")
struct AnsiStrippingTests {

    @Test("No ANSI codes unchanged")
    func noAnsiCodes() {
        #expect(stripAnsiCodes("hello world") == "hello world")
    }

    @Test("Strip color codes")
    func stripColorCodes() {
        #expect(stripAnsiCodes("\u{1B}[31mERROR\u{1B}[0m") == "ERROR")
    }

    @Test("Strip bold codes")
    func stripBoldCodes() {
        #expect(stripAnsiCodes("\u{1B}[1mBOLD\u{1B}[0m text") == "BOLD text")
    }

    @Test("Strip multiple codes")
    func stripMultipleCodes() {
        let input = "\u{1B}[32m2024-01-01\u{1B}[0m \u{1B}[33mWARN\u{1B}[0m message"
        #expect(stripAnsiCodes(input) == "2024-01-01 WARN message")
    }

    @Test("Strip 256-color sequences")
    func stripComplexSequences() {
        #expect(stripAnsiCodes("\u{1B}[38;5;196mred text\u{1B}[0m") == "red text")
    }

    @Test("Strip charset switch sequences")
    func stripCharsetSwitch() {
        #expect(stripAnsiCodes("\u{1B}(Bsome text") == "some text")
    }

    @Test("Empty string unchanged")
    func emptyString() {
        #expect(stripAnsiCodes("") == "")
    }
}

// MARK: - Log Line Filtering

@Suite("Log Line Filtering")
struct LogLineFilterTests {

    @Test("Empty line filtered out")
    func emptyLineFiltered() {
        #expect(!shouldDisplayLogLine(""))
    }

    @Test("Normal line displayed")
    func normalLineDisplayed() {
        #expect(shouldDisplayLogLine("Server started on port 3000"))
    }

    @Test("PM2 prefix with content displayed")
    func pm2PrefixWithContent() {
        #expect(shouldDisplayLogLine("3|node_ser | Server started"))
    }

    @Test("PM2 prefix with empty content filtered")
    func pm2PrefixEmpty() {
        #expect(!shouldDisplayLogLine("3|node_ser | "))
    }

    @Test("PM2 prefix with only whitespace filtered")
    func pm2PrefixOnlyWhitespace() {
        #expect(!shouldDisplayLogLine("3|node_ser |    "))
    }

    @Test("Non-PM2 line with content displayed")
    func nonPM2LineDisplayed() {
        #expect(shouldDisplayLogLine("plain log line"))
    }

    @Test("PM2 prefix with log content displayed")
    func pm2PrefixWithLogContent() {
        #expect(shouldDisplayLogLine("0|api | [INFO] Request received"))
    }
}

// MARK: - AppConfig Encoding/Decoding

@Suite("AppConfig")
struct AppConfigTests {

    @Test("Default values")
    func defaultValues() {
        let config = AppConfig()
        #expect(config.pollIntervalSeconds == 3.0)
        #expect(config.collapsedEnvironments.isEmpty)
        #expect(config.hiddenEnvironments.isEmpty)
        #expect(config.expandedInactiveEnvironments.isEmpty)
    }

    @Test("Encoding excludes expandedInactiveEnvironments")
    func encodingExcludesTransientField() throws {
        var config = AppConfig()
        config.expandedInactiveEnvironments = ["env1", "env2"]
        config.collapsedEnvironments = ["collapsed1"]
        config.hiddenEnvironments = ["hidden1"]

        let data = try JSONEncoder().encode(config)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(jsonObject["expandedInactiveEnvironments"] == nil)
        #expect(jsonObject["pollIntervalSeconds"] != nil)
        #expect(jsonObject["collapsedEnvironments"] != nil)
        #expect(jsonObject["hiddenEnvironments"] != nil)
    }

    @Test("Decoding without expandedInactiveEnvironments")
    func decodingWithoutTransientField() throws {
        let json = """
        {
            "pollIntervalSeconds": 5.0,
            "collapsedEnvironments": ["env1"],
            "hiddenEnvironments": ["env2"]
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: data)

        #expect(config.pollIntervalSeconds == 5.0)
        #expect(config.collapsedEnvironments == ["env1"])
        #expect(config.hiddenEnvironments == ["env2"])
        #expect(config.expandedInactiveEnvironments.isEmpty)
    }

    @Test("Round-trip loses expandedInactiveEnvironments")
    func roundTrip() throws {
        var config = AppConfig()
        config.pollIntervalSeconds = 10.0
        config.collapsedEnvironments = ["a", "b"]
        config.hiddenEnvironments = ["c"]
        config.expandedInactiveEnvironments = ["should_be_lost"]

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        #expect(decoded.pollIntervalSeconds == 10.0)
        #expect(decoded.collapsedEnvironments == ["a", "b"])
        #expect(decoded.hiddenEnvironments == ["c"])
        #expect(decoded.expandedInactiveEnvironments.isEmpty)
    }

    @Test("Decoding empty JSON fails (all fields required)")
    func decodingEmptyJSON() throws {
        let data = "{}".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AppConfig.self, from: data)
        }
    }

    @Test("Decoding with only required fields")
    func decodingWithRequiredFields() throws {
        let json = """
        {
            "pollIntervalSeconds": 3.0,
            "collapsedEnvironments": [],
            "hiddenEnvironments": []
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(config.pollIntervalSeconds == 3.0)
        #expect(config.collapsedEnvironments.isEmpty)
        #expect(config.hiddenEnvironments.isEmpty)
        #expect(config.expandedInactiveEnvironments.isEmpty)
    }
}

// MARK: - PM2Environment

@Suite("PM2Environment")
struct PM2EnvironmentTests {

    @Test("Default .pm2 directory")
    func defaultPM2Directory() {
        let env = PM2Environment(path: "/Users/test/.pm2")
        #expect(env.name == "default")
        #expect(env.id == "/Users/test/.pm2")
        #expect(!env.isActive)
    }

    @Test("Named .pm2-project directory")
    func namedPM2Directory() {
        let env = PM2Environment(path: "/Users/test/.pm2-myproject")
        #expect(env.name == "myproject")
    }

    @Test("Named directory with dashes")
    func namedDirectoryWithDashes() {
        let env = PM2Environment(path: "/Users/test/.pm2-my-cool-project")
        #expect(env.name == "my-cool-project")
    }

    @Test("Active state")
    func activeState() {
        let env = PM2Environment(path: "/Users/test/.pm2", isActive: true)
        #expect(env.isActive)
    }

    @Test("Hashable equality")
    func hashableEquality() {
        let env1 = PM2Environment(path: "/Users/test/.pm2")
        let env2 = PM2Environment(path: "/Users/test/.pm2")
        let env3 = PM2Environment(path: "/Users/test/.pm2-other")
        #expect(env1 == env2)
        #expect(env1 != env3)
    }

    @Test("Non-PM2 directory uses directory name")
    func nonPM2DirectoryName() {
        let env = PM2Environment(path: "/Users/test/randomdir")
        #expect(env.name == "randomdir")
    }
}

// MARK: - MetricsHistory

@Suite("MetricsHistory")
struct MetricsHistoryTests {

    @Test("Record stores samples")
    @MainActor func recordStoresSamples() throws {
        let json = """
        {
            "pid": 1234, "name": "web", "pm_id": 0,
            "monit": { "memory": 52428800, "cpu": 12.5 },
            "pm2_env": {
                "status": "online", "namespace": "default",
                "pm_exec_path": "/app/index.js", "pm_cwd": "/app",
                "exec_mode": "fork_mode", "pm_uptime": \(Int64(Date().timeIntervalSince1970 * 1000) - 60000),
                "restart_time": 0, "created_at": \(Int64(Date().timeIntervalSince1970 * 1000) - 120000),
                "pm_out_log_path": "/tmp/out.log", "pm_err_log_path": "/tmp/err.log"
            }
        }
        """
        let process = try decode(json)
        let history = MetricsHistory()

        history.record(process: process, environmentPath: "/Users/test/.pm2")
        #expect(history.history["/Users/test/.pm2:0"]?.count == 1)
        #expect(history.history["/Users/test/.pm2:0"]?.first?.cpu == 12.5)
    }

    @Test("Samples are capped at maxSamples (20)")
    @MainActor func samplesCapped() throws {
        let json = """
        {
            "pid": 1234, "name": "web", "pm_id": 5,
            "monit": { "memory": 52428800, "cpu": 1.0 },
            "pm2_env": {
                "status": "online", "namespace": "default",
                "pm_exec_path": "/app/index.js", "pm_cwd": "/app",
                "exec_mode": "fork_mode", "pm_uptime": \(Int64(Date().timeIntervalSince1970 * 1000) - 60000),
                "restart_time": 0, "created_at": \(Int64(Date().timeIntervalSince1970 * 1000) - 120000),
                "pm_out_log_path": "/tmp/out.log", "pm_err_log_path": "/tmp/err.log"
            }
        }
        """
        let process = try decode(json)
        let history = MetricsHistory()

        for _ in 0..<25 {
            history.record(process: process, environmentPath: "/home/.pm2")
        }
        #expect(history.history["/home/.pm2:5"]?.count == 20)
    }

    @Test("recordEnvironment aggregates online processes")
    @MainActor func recordEnvironmentAggregates() throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let onlineJSON = """
        {
            "pid": 1, "name": "web", "pm_id": 0,
            "monit": { "memory": 104857600, "cpu": 10.0 },
            "pm2_env": {
                "status": "online", "namespace": "default",
                "pm_exec_path": "/app/index.js", "pm_cwd": "/app",
                "exec_mode": "fork_mode", "pm_uptime": \(now - 60000),
                "restart_time": 0, "created_at": \(now - 120000),
                "pm_out_log_path": "/tmp/out.log", "pm_err_log_path": "/tmp/err.log"
            }
        }
        """
        let online2JSON = """
        {
            "pid": 2, "name": "api", "pm_id": 1,
            "monit": { "memory": 209715200, "cpu": 25.0 },
            "pm2_env": {
                "status": "online", "namespace": "default",
                "pm_exec_path": "/app/api.js", "pm_cwd": "/app",
                "exec_mode": "fork_mode", "pm_uptime": \(now - 60000),
                "restart_time": 0, "created_at": \(now - 120000),
                "pm_out_log_path": "/tmp/out.log", "pm_err_log_path": "/tmp/err.log"
            }
        }
        """
        let stoppedJSON = """
        {
            "pid": 0, "name": "worker", "pm_id": 2,
            "monit": { "memory": 52428800, "cpu": 5.0 },
            "pm2_env": {
                "status": "stopped", "namespace": "default",
                "pm_exec_path": "/app/worker.js", "pm_cwd": "/app",
                "exec_mode": "fork_mode", "pm_uptime": 0,
                "restart_time": 0, "created_at": \(now - 120000),
                "pm_out_log_path": "/tmp/out.log", "pm_err_log_path": "/tmp/err.log"
            }
        }
        """
        let processes = [try decode(onlineJSON), try decode(online2JSON), try decode(stoppedJSON)]
        let history = MetricsHistory()

        history.recordEnvironment(path: "/home/.pm2", processes: processes)

        let samples = history.history["env:/home/.pm2"]
        #expect(samples?.count == 1)
        // Should sum only online processes: 10 + 25 = 35 CPU, 100 + 200 = 300 MB
        #expect(samples?.first?.cpu == 35.0)
        #expect(samples?.first?.memoryMB == 300.0)
    }
}

// MARK: - Normalization

@Suite("MetricsHistory.normalize")
struct NormalizationTests {

    @Test("Normalizes values to 0...1")
    func normalizesRange() {
        let result = MetricsHistory.normalize([0, 5, 10])
        #expect(result == [0.0, 0.5, 1.0])
    }

    @Test("Single value returns 0.5")
    func singleValue() {
        let result = MetricsHistory.normalize([42])
        #expect(result == [0.5])
    }

    @Test("Empty array returns empty")
    func emptyArray() {
        let result = MetricsHistory.normalize([])
        #expect(result.isEmpty)
    }

    @Test("Equal values return 0.5 for all")
    func equalValues() {
        let result = MetricsHistory.normalize([7, 7, 7])
        #expect(result == [0.5, 0.5, 0.5])
    }
}
