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
        #expect(process.ports.isEmpty)
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

// MARK: - Socket-based Port Resolution

@Suite("Socket Port Resolution")
struct SocketScannerTests {

    // MARK: lsof parsing

    @Test("Parses pid → ports from lsof -Fpn output")
    func parsesLsof() {
        let output = """
        p73377
        n127.0.0.1:4321
        p84604
        n*:8888
        """
        let map = SocketScanner.parseLsof(output)
        #expect(map[73377] == [4321])
        #expect(map[84604] == [8888])
    }

    @Test("Collapses IPv4 + IPv6 bindings of the same port")
    func collapsesDualStack() {
        let output = """
        p100
        n*:3000
        n[::1]:3000
        n127.0.0.1:3000
        """
        #expect(SocketScanner.parseLsof(output)[100] == [3000])
    }

    @Test("A process listening on several distinct ports")
    func multiplePortsPerProcess() {
        let output = """
        p200
        n*:3000
        n*:9090
        """
        #expect(SocketScanner.parseLsof(output)[200] == [3000, 9090])
    }

    @Test("Empty lsof output yields no ports")
    func emptyLsof() {
        #expect(SocketScanner.parseLsof("").isEmpty)
    }

    @Test("An 'n' line before any 'p' line is ignored")
    func orphanNameLine() {
        let output = """
        n*:3000
        p500
        n*:4000
        """
        let map = SocketScanner.parseLsof(output)
        #expect(map.count == 1)
        #expect(map[500] == [4000])
    }

    @Test("Non-numeric / wildcard port tails are skipped")
    func skipsNonNumericPorts() {
        let output = """
        p600
        n*:*
        n*:5000
        """
        #expect(SocketScanner.parseLsof(output)[600] == [5000])
    }

    @Test("Unrecognised field tags are ignored")
    func ignoresOtherFieldTags() {
        let output = """
        p700
        f12
        TST=LISTEN
        n*:6000
        """
        #expect(SocketScanner.parseLsof(output)[700] == [6000])
    }

    // MARK: ps parsing

    @Test("Parses parent → children from ps output")
    func parsesPS() {
        let output = """
          84570 84001
          84604 84570
          84605 84570
        """
        let children = SocketScanner.parsePS(output)
        #expect(children[84570]?.sorted() == [84604, 84605])
        #expect(children[84001] == [84570])
    }

    @Test("Garbage / malformed ps lines are skipped")
    func parsePSSkipsGarbage() {
        let output = """
          PID  PPID
          100  1
          not a number
          200  100
        """
        let children = SocketScanner.parsePS(output)
        #expect(children[1] == [100])
        #expect(children[100] == [200])
        #expect(children.count == 2)
    }

    // MARK: tree resolution

    @Test("Resolves ports from the process itself")
    func resolvesOwnPort() {
        let snap = SocketScanner.Snapshot(portsByPID: [10: [4321]], childrenByPID: [:])
        #expect(SocketScanner.ports(forRoot: 10, in: snap) == [4321])
    }

    @Test("Resolves a child's port (npm-wrapped server case)")
    func resolvesChildPort() {
        // pid 10 = npm wrapper (no socket); its child 11 is the real server.
        let snap = SocketScanner.Snapshot(
            portsByPID: [11: [8888]],
            childrenByPID: [10: [11]]
        )
        #expect(SocketScanner.ports(forRoot: 10, in: snap) == [8888])
    }

    @Test("Resolves ports across a deeper descendant chain")
    func resolvesGrandchildPort() {
        let snap = SocketScanner.Snapshot(
            portsByPID: [12: [5000]],
            childrenByPID: [10: [11], 11: [12]]
        )
        #expect(SocketScanner.ports(forRoot: 10, in: snap) == [5000])
    }

    @Test("Merges and sorts ports from the whole subtree")
    func mergesSubtreePorts() {
        let snap = SocketScanner.Snapshot(
            portsByPID: [10: [9090], 11: [3000]],
            childrenByPID: [10: [11]]
        )
        #expect(SocketScanner.ports(forRoot: 10, in: snap) == [3000, 9090])
    }

    @Test("Filters out known debug/inspector ports")
    func filtersDebugPorts() {
        let snap = SocketScanner.Snapshot(portsByPID: [10: [3000, 9229]], childrenByPID: [:])
        #expect(SocketScanner.ports(forRoot: 10, in: snap) == [3000])
    }

    @Test("Filters debug ports and sorts the remainder")
    func filtersAndSorts() {
        let snap = SocketScanner.Snapshot(portsByPID: [10: [9090, 3000, 9229]], childrenByPID: [:])
        #expect(SocketScanner.ports(forRoot: 10, in: snap) == [3000, 9090])
    }

    @Test("A process listening on nothing resolves to no ports")
    func noListeningSockets() {
        let snap = SocketScanner.Snapshot(portsByPID: [:], childrenByPID: [:])
        #expect(SocketScanner.ports(forRoot: 10, in: snap).isEmpty)
    }

    @Test("A non-running process (pid 0) resolves to no ports")
    func zeroPid() {
        let snap = SocketScanner.Snapshot(portsByPID: [0: [3000]], childrenByPID: [:])
        #expect(SocketScanner.ports(forRoot: 0, in: snap).isEmpty)
    }

    @Test("Cyclic process references terminate")
    func cyclesTerminate() {
        // Defensive: a malformed tree where pids reference each other.
        let snap = SocketScanner.Snapshot(
            portsByPID: [10: [3000]],
            childrenByPID: [10: [11], 11: [10]]
        )
        #expect(SocketScanner.ports(forRoot: 10, in: snap) == [3000])
    }
}

// MARK: - Port Display

@Suite("Port Display")
struct PortDisplayTests {

    @Test("No ports shows nothing")
    func noPorts() {
        let s = PortDisplay.summarize([])
        #expect(s.shown.isEmpty)
        #expect(s.overflow == 0)
        #expect(s.tooltip == "")
    }

    @Test("Single port, no overflow badge")
    func singlePort() {
        let s = PortDisplay.summarize([3000])
        #expect(s.shown == [3000])
        #expect(s.overflow == 0)
        #expect(s.tooltip == ":3000")
    }

    @Test("Exactly two ports, no overflow badge")
    func twoPorts() {
        let s = PortDisplay.summarize([3000, 9090])
        #expect(s.shown == [3000, 9090])
        #expect(s.overflow == 0)
        #expect(s.tooltip == ":3000 :9090")
    }

    @Test("Three ports shows two plus +1")
    func threePorts() {
        let s = PortDisplay.summarize([6001, 6002, 6003])
        #expect(s.shown == [6001, 6002])
        #expect(s.overflow == 1)
        #expect(s.tooltip == ":6001 :6002 :6003")
    }

    @Test("Many ports collapse into +N with full tooltip")
    func manyPorts() {
        let s = PortDisplay.summarize([8000, 8001, 8002, 8003, 8004])
        #expect(s.shown == [8000, 8001])
        #expect(s.overflow == 3)
        #expect(s.tooltip == ":8000 :8001 :8002 :8003 :8004")
    }

    @Test("Custom limit is respected")
    func customLimit() {
        let s = PortDisplay.summarize([1, 2, 3], limit: 1)
        #expect(s.shown == [1])
        #expect(s.overflow == 2)
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

// MARK: - Last Activity Formatting

@Suite("Last Activity Formatting")
struct LastActivityFormattingTests {

    @Test("No log modified returns dash")
    func noLogModified() throws {
        var process = try decode("""
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online" }
        }
        """)
        #expect(process.lastLogModified == nil)
        #expect(process.formattedLastActivity == "\u{2013}")
    }

    @Test("Last activity in seconds")
    func lastActivitySeconds() throws {
        var process = try decode("""
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online" }
        }
        """)
        process.lastLogModified = Date().addingTimeInterval(-15)
        #expect(process.formattedLastActivity == "15s")
    }

    @Test("Last activity in minutes")
    func lastActivityMinutes() throws {
        var process = try decode("""
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online" }
        }
        """)
        process.lastLogModified = Date().addingTimeInterval(-300)
        #expect(process.formattedLastActivity == "5m")
    }

    @Test("Last activity in hours")
    func lastActivityHours() throws {
        var process = try decode("""
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online" }
        }
        """)
        process.lastLogModified = Date().addingTimeInterval(-7200)
        #expect(process.formattedLastActivity == "2h")
    }

    @Test("Last activity in days")
    func lastActivityDays() throws {
        var process = try decode("""
        {
            "pid": 1, "name": "x", "pm_id": 0,
            "monit": { "memory": 0, "cpu": 0.0 },
            "pm2_env": { "status": "online" }
        }
        """)
        process.lastLogModified = Date().addingTimeInterval(-172800)
        #expect(process.formattedLastActivity == "2d")
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
        #expect(config.showRepoName == true)
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
        #expect(jsonObject["showRepoName"] != nil)
    }

    @Test("Decoding without expandedInactiveEnvironments")
    func decodingWithoutTransientField() throws {
        let json = """
        {
            "pollIntervalSeconds": 5.0,
            "collapsedEnvironments": ["env1"],
            "hiddenEnvironments": ["env2"],
            "showRepoName": false
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: data)

        #expect(config.pollIntervalSeconds == 5.0)
        #expect(config.collapsedEnvironments == ["env1"])
        #expect(config.hiddenEnvironments == ["env2"])
        #expect(config.showRepoName == false)
        #expect(config.expandedInactiveEnvironments.isEmpty)
    }

    @Test("Round-trip loses expandedInactiveEnvironments")
    func roundTrip() throws {
        var config = AppConfig()
        config.pollIntervalSeconds = 10.0
        config.collapsedEnvironments = ["a", "b"]
        config.hiddenEnvironments = ["c"]
        config.showRepoName = false
        config.expandedInactiveEnvironments = ["should_be_lost"]

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        #expect(decoded.pollIntervalSeconds == 10.0)
        #expect(decoded.collapsedEnvironments == ["a", "b"])
        #expect(decoded.hiddenEnvironments == ["c"])
        #expect(decoded.showRepoName == false)
        #expect(decoded.expandedInactiveEnvironments.isEmpty)
    }

    @Test("Decoding without showRepoName defaults to true")
    func decodingWithoutShowRepoName() throws {
        let json = """
        {
            "pollIntervalSeconds": 3.0,
            "collapsedEnvironments": [],
            "hiddenEnvironments": []
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(config.showRepoName == true)
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
            "hiddenEnvironments": [],
            "showRepoName": true
        }
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(config.pollIntervalSeconds == 3.0)
        #expect(config.collapsedEnvironments.isEmpty)
        #expect(config.hiddenEnvironments.isEmpty)
        #expect(config.showRepoName == true)
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

// MARK: - GitInfo Resolution

@Suite("GitInfo")
struct GitInfoTests {

    @Test("resolveGitInfo returns repo name and branch for valid git directory")
    func resolveFromGitDir() throws {
        // Use the current repo as a known git directory
        let cwd = FileManager.default.currentDirectoryPath
        let gitInfo = PM2Environment.resolveGitInfo(from: cwd)
        #expect(gitInfo != nil)
        #expect(gitInfo?.repoName.isEmpty == false)
        #expect(gitInfo?.branch.isEmpty == false)
    }

    @Test("resolveGitInfo returns nil for non-git directory")
    func resolveFromNonGitDir() {
        let gitInfo = PM2Environment.resolveGitInfo(from: "/tmp")
        #expect(gitInfo == nil)
    }

    @Test("resolveGitInfo returns nil for empty path")
    func resolveFromEmptyPath() {
        let gitInfo = PM2Environment.resolveGitInfo(from: "")
        #expect(gitInfo == nil)
    }

    @Test("displayBranch with no stripping")
    func displayBranchNoStripping() {
        let gi = GitInfo(repoName: "repo", branch: "fredrivett/eng-3338-next-button-fix")
        #expect(gi.displayBranch(stripPrefix: false, stripTicket: false) == "fredrivett/eng-3338-next-button-fix")
    }

    // -- Strip prefix with slash separator --

    @Test("displayBranch strips slash prefix with ticket")
    func displayBranchStripSlashPrefix() {
        let gi = GitInfo(repoName: "repo", branch: "fredrivett/eng-3338-next-button-fix")
        #expect(gi.displayBranch(stripPrefix: true, stripTicket: false) == "eng-3338-next-button-fix")
    }

    @Test("displayBranch strips slash prefix without ticket")
    func displayBranchStripSlashPrefixNoTicket() {
        let gi = GitInfo(repoName: "repo", branch: "fredrivett/my-feature")
        #expect(gi.displayBranch(stripPrefix: true, stripTicket: false) == "my-feature")
    }

    // -- Strip prefix with dash separator --

    @Test("displayBranch strips dash prefix with ticket")
    func displayBranchStripDashPrefix() {
        let gi = GitInfo(repoName: "repo", branch: "fredrivett-eng-3338-next-button-fix")
        #expect(gi.displayBranch(stripPrefix: true, stripTicket: false) == "eng-3338-next-button-fix")
    }

    @Test("displayBranch does not strip dash prefix without ticket")
    func displayBranchDashPrefixNoTicket() {
        // No ticket pattern found, no slash — nothing to strip
        let gi = GitInfo(repoName: "repo", branch: "fredrivett-my-feature")
        #expect(gi.displayBranch(stripPrefix: true, stripTicket: false) == "fredrivett-my-feature")
    }

    // -- Strip ticket --

    @Test("displayBranch strips ticket only")
    func displayBranchStripTicket() {
        let gi = GitInfo(repoName: "repo", branch: "eng-3338-next-button-fix")
        #expect(gi.displayBranch(stripPrefix: false, stripTicket: true) == "next-button-fix")
    }

    @Test("displayBranch strips ticket case-insensitively")
    func displayBranchCaseInsensitive() {
        let gi = GitInfo(repoName: "repo", branch: "ENG-100-fix")
        #expect(gi.displayBranch(stripPrefix: false, stripTicket: true) == "fix")
    }

    @Test("displayBranch strips short team key ticket")
    func displayBranchShortTeamKey() {
        let gi = GitInfo(repoName: "repo", branch: "FE-12-button-fix")
        #expect(gi.displayBranch(stripPrefix: false, stripTicket: true) == "button-fix")
    }

    // -- Strip both --

    @Test("displayBranch strips both with slash")
    func displayBranchStripBothSlash() {
        let gi = GitInfo(repoName: "repo", branch: "fredrivett/eng-3338-next-button-fix")
        #expect(gi.displayBranch(stripPrefix: true, stripTicket: true) == "next-button-fix")
    }

    @Test("displayBranch strips both with dash")
    func displayBranchStripBothDash() {
        let gi = GitInfo(repoName: "repo", branch: "fredrivett-eng-3338-next-button-fix")
        #expect(gi.displayBranch(stripPrefix: true, stripTicket: true) == "next-button-fix")
    }

    // -- Edge cases --

    @Test("displayBranch no-op when no prefix or ticket")
    func displayBranchNoMatch() {
        let gi = GitInfo(repoName: "repo", branch: "main")
        #expect(gi.displayBranch(stripPrefix: true, stripTicket: true) == "main")
    }

    @Test("displayBranch with multiple slashes strips at ticket")
    func displayBranchMultipleSlashes() {
        let gi = GitInfo(repoName: "repo", branch: "feature/team/eng-99-thing")
        #expect(gi.displayBranch(stripPrefix: true, stripTicket: true) == "thing")
    }

    @Test("displayBranch ticket-only branch keeps ticket when not stripping ticket")
    func displayBranchTicketOnly() {
        let gi = GitInfo(repoName: "repo", branch: "eng-3338-fix")
        #expect(gi.displayBranch(stripPrefix: true, stripTicket: false) == "eng-3338-fix")
    }

    @Test("GitInfo is hashable")
    func hashable() {
        let a = GitInfo(repoName: "repo", branch: "main")
        let b = GitInfo(repoName: "repo", branch: "main")
        let c = GitInfo(repoName: "repo", branch: "dev")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("PM2Environment gitInfo is nil by default")
    func defaultGitInfoNil() {
        let env = PM2Environment(path: "/Users/test/.pm2-myproject")
        #expect(env.gitInfo == nil)
    }

    @Test("PM2Environment gitInfo can be set")
    func setGitInfo() {
        var env = PM2Environment(path: "/Users/test/.pm2-myproject")
        env.gitInfo = GitInfo(repoName: "myrepo", branch: "feature/x")
        #expect(env.gitInfo?.repoName == "myrepo")
        #expect(env.gitInfo?.branch == "feature/x")
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

// MARK: - pm2 stdout JSON extraction

@Suite("PM2Service.extractJSON")
struct ExtractJSONTests {

    private func string(_ data: Data) -> String {
        String(data: data, encoding: .utf8)!
    }

    @Test("Pure JSON array is returned unchanged")
    func pureJSON() {
        let json = #"[{"pid":1}]"#
        let result = PM2Service.extractJSON(from: Data(json.utf8))
        #expect(string(result) == json)
    }

    @Test("Strips the ANSI-colored out-of-date banner before the JSON")
    func stripsVersionBanner() throws {
        // Mirrors real `pm2 jlist` stdout when the in-memory daemon version
        // differs from the local CLI: a leading blank line, ANSI-colored
        // ">>>>" notices, then the JSON array on its own line.
        let esc = "\u{1B}"
        let banner = """
        \n\(esc)[31m\(esc)[1m>>>> In-memory PM2 is out-of-date, do:\(esc)[22m\(esc)[39m
        \(esc)[31m\(esc)[1m>>>> $ pm2 update\(esc)[22m\(esc)[39m
        In memory PM2 version: \(esc)[34m\(esc)[1m7.0.1\(esc)[22m\(esc)[39m
        Local PM2 version: \(esc)[34m\(esc)[1m7.0.3\(esc)[22m\(esc)[39m\n\n
        """
        let json = #"[{"pid":260,"name":"web","pm_id":0,"monit":{"memory":100,"cpu":0},"pm2_env":{"status":"online"}}]"#
        let result = PM2Service.extractJSON(from: Data((banner + json).utf8))
        #expect(string(result) == json)
        // And the trimmed payload decodes cleanly.
        let procs = try JSONDecoder().decode([PM2Process].self, from: result)
        #expect(procs.count == 1)
        #expect(procs[0].name == "web")
    }

    @Test("Empty JSON array after a banner is preserved")
    func emptyArrayAfterBanner() {
        let esc = "\u{1B}"
        let raw = "\(esc)[31mnotice\(esc)[39m\n[]"
        let result = PM2Service.extractJSON(from: Data(raw.utf8))
        #expect(string(result) == "[]")
    }

    @Test("Returns input unchanged when no JSON bracket is present")
    func noBracket() {
        let raw = "pm2 daemon not responding"
        let result = PM2Service.extractJSON(from: Data(raw.utf8))
        #expect(string(result) == raw)
    }
}

// MARK: - Bind port parsing

@Suite("PM2Process.parsePort")
struct ParsePortTests {

    @Test("uvicorn --host --port form")
    func uvicornForm() {
        let args = ["src.scripts.asgi:app", "--host", "0.0.0.0", "--port", "5008", "--workers", "2"]
        #expect(PM2Process.parsePort(fromArgs: args) == 5008)
    }

    @Test("hypercorn/gunicorn --bind host:port form")
    func bindForm() {
        let args = ["--workers", "2", "--bind", "0.0.0.0:5004", "src.scripts.asgi:app"]
        #expect(PM2Process.parsePort(fromArgs: args) == 5004)
    }

    @Test("short -p flag")
    func shortFlag() {
        #expect(PM2Process.parsePort(fromArgs: ["-p", "3000"]) == 3000)
    }

    @Test("--port=N equals form")
    func equalsForm() {
        #expect(PM2Process.parsePort(fromArgs: ["--port=8080"]) == 8080)
    }

    @Test("-b=host:port equals form")
    func bindEqualsForm() {
        #expect(PM2Process.parsePort(fromArgs: ["-b=127.0.0.1:9000"]) == 9000)
    }

    @Test("--bind :port with no host")
    func bindNoHost() {
        #expect(PM2Process.parsePort(fromArgs: ["--bind", ":5555"]) == 5555)
    }

    @Test("Falls back to PORT env when args have no port")
    func portEnvFallback() {
        #expect(PM2Process.parsePort(fromArgs: ["server.js"], portEnv: "4321") == 4321)
    }

    @Test("Args take precedence over PORT env")
    func argsBeatEnv() {
        #expect(PM2Process.parsePort(fromArgs: ["--port", "5008"], portEnv: "9999") == 5008)
    }

    @Test("No port anywhere returns nil")
    func noPort() {
        #expect(PM2Process.parsePort(fromArgs: ["worker.js", "--workers", "2"]) == nil)
    }

    @Test("Out-of-range port is rejected")
    func outOfRange() {
        #expect(PM2Process.parsePort(fromArgs: ["--port", "99999"]) == nil)
        #expect(PM2Process.parsePort(fromArgs: ["--port", "0"]) == nil)
    }

    @Test("Non-numeric port value is ignored")
    func nonNumeric() {
        #expect(PM2Process.parsePort(fromArgs: ["--port", "auto"]) == nil)
    }
}

// MARK: - Address-in-use log detection

@Suite("PM2Service.logReportsAddressInUse")
struct AddressInUseTests {

    @Test("Detects Python errno phrasing")
    func pythonErrno() {
        #expect(PM2Service.logReportsAddressInUse("ERROR:    [Errno 48] Address already in use"))
    }

    @Test("Detects Node EADDRINUSE")
    func nodeEaddrinuse() {
        #expect(PM2Service.logReportsAddressInUse("Error: listen EADDRINUSE: address already in use :::3000"))
    }

    @Test("Case-insensitive")
    func caseInsensitive() {
        #expect(PM2Service.logReportsAddressInUse("ADDRESS ALREADY IN USE"))
    }

    @Test("Unrelated log lines are not flagged")
    func unrelated() {
        #expect(!PM2Service.logReportsAddressInUse("INFO: Application startup complete on port 5008"))
    }
}
