import Foundation
import Network

struct ApplyConfigDraft: Equatable {
    var hardwarePort: String = ""
    var method: IpConfigurationType = .dhcp
    var ipv4: String = ""
    var subnetMask: String = ""
    var router: String = ""
    var dnsText: String = ""
}

enum NetworkConfigurator {
    private static var portCache: (at: Date, value: [(port: String, device: String)])?

    static func hardwarePorts() -> [(port: String, device: String)] {
        if let cache = portCache, Date().timeIntervalSince(cache.at) < 30 {
            return cache.value
        }
        guard let output = Shell.run("/usr/sbin/networksetup", arguments: ["-listallhardwareports"]) else {
            return portCache?.value ?? []
        }
        var results: [(String, String)] = []
        var currentPort: String?
        for line in output.split(separator: "\n") {
            let text = String(line)
            if text.hasPrefix("Hardware Port: ") {
                currentPort = String(text.dropFirst("Hardware Port: ".count))
            } else if text.hasPrefix("Device: "), let currentPort {
                results.append((currentPort, String(text.dropFirst("Device: ".count))))
            }
        }
        portCache = (Date(), results)
        return results
    }

    static func port(forBSD bsd: String) -> String? {
        hardwarePorts().first(where: { $0.device == bsd })?.port
    }

    static func apply(_ draft: ApplyConfigDraft) -> Result<String, HostValidationError> {
        let port = draft.hardwarePort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !port.isEmpty else {
            return .failure(HostValidationError(message: "Choose an adapter"))
        }
        guard hardwarePorts().contains(where: { $0.port == port }) else {
            return .failure(HostValidationError(message: "Unknown adapter"))
        }

        var commands: [[String]] = []
        switch draft.method {
        case .dhcp:
            commands.append(["-setdhcp", port])
        case .staticConfig:
            guard case .success(let ip) = ipv4(draft.ipv4) else {
                return .failure(HostValidationError(message: "Static IP is invalid"))
            }
            guard case .success(let mask) = ipv4(draft.subnetMask) else {
                return .failure(HostValidationError(message: "Subnet mask is invalid"))
            }
            guard case .success(let router) = ipv4(draft.router) else {
                return .failure(HostValidationError(message: "Router is invalid"))
            }
            commands.append(["-setmanual", port, ip, mask, router])
        case .unknown:
            return .failure(HostValidationError(message: "Choose DHCP or Static"))
        }

        let dns = parseDNS(draft.dnsText)
        switch dns {
        case .failure(let error):
            return .failure(error)
        case .success(let servers):
            if servers.isEmpty {
                commands.append(["-setdnsservers", port, "Empty"])
            } else {
                commands.append(["-setdnsservers", port] + servers)
            }
        }

        for args in commands {
            if let error = runNetworkSetup(args) {
                return .failure(HostValidationError(message: error))
            }
        }
        return .success("Applied \(draft.method.rawValue) on \(port)")
    }

    private static func ipv4(_ raw: String) -> Result<String, HostValidationError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard IPv4Address(trimmed) != nil else {
            return .failure(HostValidationError(message: "Invalid IPv4: \(trimmed)"))
        }
        return .success(trimmed)
    }

    private static func parseDNS(_ raw: String) -> Result<[String], HostValidationError> {
        let parts = raw
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var servers: [String] = []
        for part in parts {
            guard IPv4Address(part) != nil || IPv6Address(part) != nil else {
                return .failure(HostValidationError(message: "Invalid DNS server: \(part)"))
            }
            servers.append(part)
        }
        return .success(servers)
    }

    private static func runNetworkSetup(_ arguments: [String]) -> String? {
        if let error = run("/usr/sbin/networksetup", arguments: arguments, privileged: false) {
            if error.localizedCaseInsensitiveContains("permission")
                || error.localizedCaseInsensitiveContains("not permitted")
                || error.localizedCaseInsensitiveContains("authorized")
                || error.localizedCaseInsensitiveContains("privileges")
            {
                return run("/usr/sbin/networksetup", arguments: arguments, privileged: true)
            }
            return error
        }
        return nil
    }

    private static func run(_ path: String, arguments: [String], privileged: Bool) -> String? {
        if privileged {
            let command = ([path] + arguments).map(quote).joined(separator: " ")
            let script = "do shell script \(quote(command)) with administrator privileges"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let err = Pipe()
            process.standardOutput = Pipe()
            process.standardError = err
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return error.localizedDescription
            }
            if process.terminationStatus == 0 {
                return nil
            }
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                ?? "Administrator approval failed"
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return error.localizedDescription
        }
        if process.terminationStatus == 0 {
            return nil
        }
        let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            ?? "networksetup failed"
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
