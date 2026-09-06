import Foundation
import SystemConfiguration

struct DHCPLeaseInfo: Equatable, Sendable {
    var obtained: String?
    var expires: String?
    var server: String?
}

enum DHCPLeaseReader {
    private static var cache: [String: (at: Date, info: DHCPLeaseInfo)] = [:]

    static func read(bsd: String) -> DHCPLeaseInfo {
        if let cached = cache[bsd], Date().timeIntervalSince(cached.at) < 30 {
            return cached.info
        }
        var info = readFromStore(bsd: bsd)
        let packet = Shell.run("/usr/sbin/ipconfig", arguments: ["getpacket", bsd]) ?? ""
        if info.server == nil {
            info.server = firstMatch(#"server_identifier \(ip\): ([0-9.]+)"#, in: packet)
        }
        if info.expires == nil, let seconds = uintOption("lease_time", in: packet) {
            info.expires = "in \(formatDuration(TimeInterval(seconds)))"
        }
        if info.obtained == nil, let start = uintOption("lease_start", in: packet) {
            info.obtained = formatDate(Date(timeIntervalSince1970: TimeInterval(start)))
        }
        cache[bsd] = (Date(), info)
        return info
    }

    private static func readFromStore(bsd: String) -> DHCPLeaseInfo {
        var info = DHCPLeaseInfo()
        guard let store = SCDynamicStoreCreate(nil, "NightwireLease" as CFString, nil, nil) else {
            return info
        }
        guard let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/[^/]+/DHCP" as CFString) as? [String] else {
            return info
        }
        for key in keys {
            let ipv4Key = key.replacingOccurrences(of: "/DHCP", with: "/IPv4")
            guard let ipv4 = SCDynamicStoreCopyValue(store, ipv4Key as CFString) as? [String: Any],
                  let iface = ipv4["InterfaceName"] as? String,
                  iface == bsd
            else { continue }

            guard let dhcp = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] else {
                continue
            }
            if let expiration = dhcp["LeaseExpirationTime"] as? Date {
                info.expires = formatDate(expiration)
            } else if let expiration = dhcp["LeaseExpirationTime"] as? TimeInterval {
                info.expires = formatDate(Date(timeIntervalSince1970: expiration))
            }
            if let start = dhcp["LeaseStartTime"] as? Date {
                info.obtained = formatDate(start)
            } else if let start = dhcp["Lease"] as? Date {
                info.obtained = formatDate(start)
            }
            if let server = dhcp["ServerIdentifier"] as? String {
                info.server = server
            }
        }
        return info
    }

    private static func uintOption(_ name: String, in text: String) -> UInt32? {
        let hex = firstMatch("\(name) \\(uint32\\): (0x[0-9a-fA-F]+)", in: text)
        if let hex {
            return UInt32(hex.dropFirst(2), radix: 16)
        }
        if let dec = firstMatch("\(name) \\(uint32\\): ([0-9]+)", in: text) {
            return UInt32(dec)
        }
        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captured = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captured])
    }

    private static func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(minutes, 1))m"
    }
}
