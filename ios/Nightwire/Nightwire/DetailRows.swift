import Foundation

enum DetailRows {
    struct Row: Equatable, Identifiable {
        var id: String { title }
        var title: String
        var value: String
        var copyValue: String
    }

    static func make(iface: LocalInterface, publicIPText: String) -> [Row] {
        var rows: [Row] = [
            row("IP address", iface.ipv4.isEmpty ? "None" : iface.ipv4, copy: iface.ipv4),
            row("CIDR", iface.cidr.isEmpty ? "None" : iface.cidr, copy: iface.ipv4.isEmpty ? "" : iface.cidr),
            row("MAC", iface.mac, copy: iface.mac == "—" ? "" : iface.mac),
            row("Link speed", iface.linkSpeedText, copy: iface.linkSpeedText),
            row("Gateway", iface.gateway.isEmpty ? "None" : iface.gateway, copy: iface.gateway),
            row("DNS", iface.dnsText, copy: iface.dnsServers.isEmpty ? "" : iface.dnsText)
        ]
        if let subnet = iface.subnet {
            rows.append(row("Network", subnet.networkAddress, copy: subnet.networkAddress))
            rows.append(row("Broadcast", subnet.broadcastAddress, copy: subnet.broadcastAddress))
            rows.append(row("Host range", subnet.hostRange, copy: subnet.hostRange))
            rows.append(row("Usable hosts", "\(subnet.usableHosts)", copy: "\(subnet.usableHosts)"))
        }
        rows.append(contentsOf: wifiRows(iface))
        if let rank = iface.serviceRank {
            rows.append(row("Service order", "#\(rank)", copy: "\(rank)"))
        }
        if let obtained = iface.dhcpLeaseObtained {
            rows.append(row("DHCP obtained", obtained, copy: obtained))
        }
        if let expires = iface.dhcpLeaseExpires {
            rows.append(row("DHCP expires", expires, copy: expires))
        }
        if let server = iface.dhcpServer {
            rows.append(row("DHCP server", server, copy: server))
        }
        rows.append(row("Public IP", publicIPText, copy: isCopyable(publicIPText) ? publicIPText : ""))
        return rows
    }

    static func copyAll(iface: LocalInterface, publicIP: String?) -> String {
        var lines = [
            "Interface: \(iface.title)",
            "IP: \(iface.ipv4.isEmpty ? "None" : iface.ipv4)",
            "Config: \(iface.configuration.rawValue)",
            "CIDR: \(iface.cidr)",
            "MAC: \(iface.mac)",
            "Link speed: \(iface.linkSpeedText)",
            "Gateway: \(iface.gateway.isEmpty ? "None" : iface.gateway)",
            "DNS: \(iface.dnsText)"
        ]
        if let subnet = iface.subnet {
            lines.append("Network: \(subnet.networkAddress)")
            lines.append("Broadcast: \(subnet.broadcastAddress)")
            lines.append("Host range: \(subnet.hostRange)")
            lines.append("Usable hosts: \(subnet.usableHosts)")
        }
        if let ssid = iface.wifiSSID { lines.append("Wi-Fi SSID: \(ssid)") }
        if let bssid = iface.wifiBSSID { lines.append("Wi-Fi BSSID: \(bssid)") }
        if let channel = iface.wifiChannel { lines.append("Wi-Fi channel: \(channel)") }
        if let band = iface.wifiBand { lines.append("Wi-Fi band: \(band)") }
        if let phy = iface.wifiPHY { lines.append("Wi-Fi radio: \(phy)") }
        if let rssi = iface.wifiRSSI { lines.append("Wi-Fi signal: \(rssi)") }
        if let rank = iface.serviceRank { lines.append("Service order: \(rank)") }
        if let obtained = iface.dhcpLeaseObtained { lines.append("DHCP obtained: \(obtained)") }
        if let expires = iface.dhcpLeaseExpires { lines.append("DHCP expires: \(expires)") }
        if let server = iface.dhcpServer { lines.append("DHCP server: \(server)") }
        if let publicIP, isCopyable(publicIP) { lines.append("Public IP: \(publicIP)") }
        return lines.joined(separator: "\n")
    }

    static func isCopyable(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "—" && trimmed != "…" && trimmed != "Unavailable"
    }

    static func wifiFootnote(for iface: LocalInterface) -> String? {
        guard iface.kind == .wifi else { return nil }
        let missingIdentity = iface.wifiSSID == nil && iface.wifiBSSID == nil && iface.wifiRSSI == nil
        if missingIdentity {
            return "SSID, BSSID, and signal need Location permission and the Wi-Fi Information capability. Channel, band, and radio are not available on iOS."
        }
        if iface.wifiChannel == nil && iface.wifiBand == nil && iface.wifiPHY == nil {
            return "iOS does not provide channel, band, or radio."
        }
        return nil
    }

    private static func wifiRows(_ iface: LocalInterface) -> [Row] {
        let fields: [(String, String?)] = [
            ("SSID", iface.wifiSSID),
            ("BSSID", iface.wifiBSSID),
            ("Channel", iface.wifiChannel),
            ("Band", iface.wifiBand),
            ("Radio", iface.wifiPHY),
            ("Signal", iface.wifiRSSI)
        ]
        if iface.kind == .wifi {
            return fields.map { title, value in
                if let value, !value.isEmpty {
                    return row(title, value, copy: value)
                }
                return row(title, "Unavailable", copy: "")
            }
        }
        return fields.compactMap { title, value in
            guard let value, !value.isEmpty else { return nil }
            return row(title, value, copy: value)
        }
    }

    private static func row(_ title: String, _ value: String, copy: String) -> Row {
        Row(title: title, value: value, copyValue: copy)
    }
}
