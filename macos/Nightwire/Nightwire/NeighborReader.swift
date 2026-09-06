import Foundation

struct NeighborDevice: Identifiable, Equatable, Sendable {
    var id: String { "\(ip)|\(mac)|\(iface)" }
    let ip: String
    let mac: String
    let iface: String
    let vendor: String
}

enum NeighborReader {
    static func read() -> [NeighborDevice] {
        let output = Shell.run("/usr/sbin/arp", arguments: ["-an"]) ?? ""
        var neighbors: [NeighborDevice] = []
        let pattern = #"\((\d+\.\d+\.\d+\.\d+)\) at ([0-9a-fA-F:]+) on (\S+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        for match in regex.matches(in: output, range: range) {
            guard
                let ipRange = Range(match.range(at: 1), in: output),
                let macRange = Range(match.range(at: 2), in: output),
                let ifaceRange = Range(match.range(at: 3), in: output)
            else { continue }

            let ip = String(output[ipRange])
            let mac = String(output[macRange]).uppercased()
            let iface = String(output[ifaceRange])
            if ip.hasPrefix("224.") || ip.hasPrefix("239.") || ip.hasSuffix(".255") { continue }
            if mac == "(INCOMPLETE)" || mac.contains("INCOMPLETE") { continue }

            neighbors.append(
                NeighborDevice(
                    ip: ip,
                    mac: mac,
                    iface: iface,
                    vendor: MACVendor.lookup(mac)
                )
            )
        }

        return neighbors.sorted { lhs, rhs in
            lhs.ip.localizedStandardCompare(rhs.ip) == .orderedAscending
        }
    }
}

enum MACVendor {
    static func lookup(_ mac: String) -> String {
        let prefix = mac
            .split(separator: ":")
            .prefix(3)
            .map { $0.uppercased() }
            .joined(separator: ":")
        return table[prefix] ?? "Unknown"
    }

    private static let table: [String: String] = [
        "00:00:0C": "Cisco",
        "00:1A:11": "Google",
        "00:1B:63": "Apple",
        "00:1C:B3": "Apple",
        "00:1E:C2": "Apple",
        "00:21:E9": "Apple",
        "00:23:12": "Apple",
        "00:23:32": "Apple",
        "00:25:00": "Apple",
        "00:26:08": "Apple",
        "00:26:BB": "Apple",
        "00:50:56": "VMware",
        "00:0C:29": "VMware",
        "00:1D:D8": "Microsoft",
        "00:15:5D": "Microsoft",
        "28:11:A5": "Brocade",
        "3C:06:30": "Apple",
        "3C:22:FB": "Apple",
        "40:B0:76": "ASUS",
        "48:A1:95": "Apple",
        "4C:32:75": "Apple",
        "50:32:37": "Apple",
        "54:72:4F": "Apple",
        "5C:F9:38": "Apple",
        "60:03:08": "Apple",
        "64:20:0C": "Apple",
        "68:D9:3C": "Apple",
        "70:56:81": "Apple",
        "78:31:C1": "Apple",
        "7C:6D:62": "Apple",
        "80:E6:50": "Apple",
        "88:66:A5": "Apple",
        "8C:85:90": "Apple",
        "98:01:A7": "Apple",
        "A4:83:E7": "Apple",
        "A8:86:DD": "Apple",
        "AC:87:A3": "Apple",
        "DC:A6:32": "Raspberry Pi",
        "E4:5F:01": "Raspberry Pi",
        "B0:BE:76": "TP-Link",
        "50:C7:BF": "TP-Link",
        "C0:25:E9": "TP-Link",
        "D8:0D:17": "TP-Link",
        "E8:48:B8": "TP-Link",
        "F0:9F:C2": "Ubiquiti",
        "24:5A:4C": "Ubiquiti",
        "78:8A:20": "Ubiquiti",
        "18:E8:29": "Ubiquiti",
        "FC:EC:DA": "Ubiquiti",
        "00:17:88": "Philips Hue",
        "B8:27:EB": "Raspberry Pi",
        "D0:03:4B": "Apple",
        "F0:18:98": "Apple",
        "F4:0F:24": "Apple",
        "F8:FF:C2": "Apple",
        "AC:DE:48": "Apple",
        "00:1A:2B": "Ayecom",
        "08:00:27": "VirtualBox",
        "AA:00:04": "DEC",
        "00:E0:4C": "Realtek",
        "52:54:00": "QEMU/KVM"
    ]
}

enum Shell {
    static func run(_ launchPath: String, arguments: [String], timeout: TimeInterval = 4) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
