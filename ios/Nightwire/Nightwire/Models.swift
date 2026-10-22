import Darwin
import Foundation

enum InterfaceKind: String, Equatable, Hashable, Sendable {
    case usbEthernet
    case wifi
    case cellular
    case other
}

enum IpConfigurationType: String, Equatable, Hashable, Sendable {
    case dhcp = "DHCP"
    case staticConfig = "Static"
    case unknown = "—"
}

struct SubnetInfo: Equatable, Sendable {
    let networkAddress: String
    let broadcastAddress: String
    let firstHost: String
    let lastHost: String
    let usableHosts: Int

    var hostRange: String {
        "\(firstHost) – \(lastHost)"
    }
}

enum IPv4 {
    static func parse(_ text: String) -> UInt32? {
        var address = in_addr()
        guard inet_pton(AF_INET, text, &address) == 1 else { return nil }
        return UInt32(bigEndian: address.s_addr)
    }

    static func format(_ value: UInt32) -> String {
        var address = in_addr(s_addr: value.bigEndian)
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            return "0.0.0.0"
        }
        return String(cString: buffer)
    }
}

enum SubnetCalculator {
    static func calculate(ip: String, prefix: Int) -> SubnetInfo? {
        guard prefix >= 0, prefix <= 32, let value = IPv4.parse(ip) else { return nil }
        let mask: UInt32 = prefix == 0 ? 0 : UInt32.max << (32 - prefix)
        let network = value & mask
        let broadcast = network | ~mask
        let first = prefix >= 31 ? network : network &+ 1
        let last = prefix >= 31 ? broadcast : broadcast &- 1
        let usable: Int
        if prefix >= 31 {
            usable = Int(broadcast &- network &+ 1)
        } else {
            usable = max(0, Int(broadcast &- network &- 1))
        }
        return SubnetInfo(
            networkAddress: IPv4.format(network),
            broadcastAddress: IPv4.format(broadcast),
            firstHost: IPv4.format(first),
            lastHost: IPv4.format(last),
            usableHosts: usable
        )
    }
}

struct LocalInterface: Identifiable, Equatable, Sendable {
    var id: String { bsdName }

    /// BSD name such as `en2` or `pdp_ip0`.
    let bsdName: String
    let displayName: String
    let kind: InterfaceKind
    let ipv4: String
    let prefixLength: Int?
    let cidr: String
    let mac: String
    let gateway: String
    let dnsServers: [String]
    let configuration: IpConfigurationType
    let linkSpeedBps: UInt64
    /// True when iOS is using this interface for the default route.
    let isPrimary: Bool
    let isPluggedIn: Bool
    let hasLink: Bool
    let hasGlobalIPv4: Bool
    let wifiSSID: String?
    let wifiBSSID: String?
    let wifiChannel: String?
    let wifiBand: String?
    let wifiPHY: String?
    let wifiRSSI: String?
    let subnet: SubnetInfo?
    let serviceRank: Int?
    let dhcpLeaseObtained: String?
    let dhcpLeaseExpires: String?
    let dhcpServer: String?

    init(
        bsdName: String,
        displayName: String,
        kind: InterfaceKind,
        ipv4: String = "",
        prefixLength: Int? = nil,
        cidr: String = "None",
        mac: String = "—",
        gateway: String = "",
        dnsServers: [String] = [],
        configuration: IpConfigurationType = .unknown,
        linkSpeedBps: UInt64 = 0,
        isPrimary: Bool = false,
        isPluggedIn: Bool = false,
        hasLink: Bool = false,
        hasGlobalIPv4: Bool = false,
        wifiSSID: String? = nil,
        wifiBSSID: String? = nil,
        wifiChannel: String? = nil,
        wifiBand: String? = nil,
        wifiPHY: String? = nil,
        wifiRSSI: String? = nil,
        subnet: SubnetInfo? = nil,
        serviceRank: Int? = nil,
        dhcpLeaseObtained: String? = nil,
        dhcpLeaseExpires: String? = nil,
        dhcpServer: String? = nil
    ) {
        self.bsdName = bsdName
        self.displayName = displayName
        self.kind = kind
        self.ipv4 = ipv4
        self.prefixLength = prefixLength
        self.cidr = cidr
        self.mac = mac
        self.gateway = gateway
        self.dnsServers = dnsServers
        self.configuration = configuration
        self.linkSpeedBps = linkSpeedBps
        self.isPrimary = isPrimary
        self.isPluggedIn = isPluggedIn
        self.hasLink = hasLink
        self.hasGlobalIPv4 = hasGlobalIPv4
        self.wifiSSID = wifiSSID
        self.wifiBSSID = wifiBSSID
        self.wifiChannel = wifiChannel
        self.wifiBand = wifiBand
        self.wifiPHY = wifiPHY
        self.wifiRSSI = wifiRSSI
        self.subnet = subnet
        self.serviceRank = serviceRank
        self.dhcpLeaseObtained = dhcpLeaseObtained
        self.dhcpLeaseExpires = dhcpLeaseExpires
        self.dhcpServer = dhcpServer
    }

    var dnsText: String {
        dnsServers.isEmpty ? "None" : dnsServers.joined(separator: ", ")
    }

    var linkSpeedText: String {
        LinkSpeed.format(linkSpeedBps)
    }

    var title: String {
        displayName == bsdName ? bsdName : "\(displayName)  ·  \(bsdName)"
    }

    var menuTitle: String {
        isPrimary ? "\(title)  ·  Primary" : title
    }

    var candidate: InterfaceCandidate {
        InterfaceCandidate(
            name: bsdName,
            kind: kind,
            isPluggedIn: isPluggedIn,
            hasGlobalIPv4: hasGlobalIPv4,
            isDefaultPath: isPrimary
        )
    }
}

struct NeighborDevice: Identifiable, Equatable, Sendable {
    var id: String { "\(ip)|\(mac)|\(iface)" }
    let ip: String
    let mac: String
    let iface: String
    let vendor: String
}

enum MACAddress {
    static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let hex = raw.uppercased().filter(\.isHexDigit)
        guard hex.count == 12, !hex.allSatisfy({ $0 == "0" }) else { return nil }
        return stride(from: 0, to: 12, by: 2).map { offset -> String in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return String(hex[start..<end])
        }.joined(separator: ":")
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

enum LinkSpeed {
    /// Maps an `IFM_SUBTYPE` value from `<net/if_media.h>` to bits per second.
    static func bitsPerSecond(subtype: Int32) -> UInt64 {
        switch subtype {
        case 3, 4, 5, 12, 13:
            return 10_000_000
        case 6, 7, 8, 9, 10:
            return 100_000_000
        case 11, 14, 15, 16, 24, 25:
            return 1_000_000_000
        case 22:
            return 2_500_000_000
        case 23:
            return 5_000_000_000
        case 18, 19, 20, 21, 26, 27, 28, 29:
            return 10_000_000_000
        default:
            return 0
        }
    }

    static func format(_ bps: UInt64) -> String {
        if bps >= 1_000_000_000 {
            let value = Double(bps) / 1_000_000_000
            return String(format: value >= 10 ? "%.0f Gbps" : "%.1f Gbps", value)
        }
        if bps >= 1_000_000 {
            let value = Double(bps) / 1_000_000
            return String(format: value >= 10 ? "%.0f Mbps" : "%.1f Mbps", value)
        }
        if bps > 0 {
            return "\(bps) bps"
        }
        return "Unknown"
    }
}

enum LinkState {
    /// `status` is `ifmediareq.ifm_status`. Bit 0 is IFM_AVALID, bit 1 is IFM_ACTIVE.
    static func hasLink(hasGlobalIPv4: Bool, isRunning: Bool, mediaValid: Bool, mediaStatus: Int32) -> Bool {
        if hasGlobalIPv4 { return true }
        if mediaValid && (mediaStatus & 0x1) != 0 {
            return (mediaStatus & 0x2) != 0
        }
        return isRunning
    }
}

enum PlugState {
    static func isPluggedIn(kind: InterfaceKind, isUp: Bool, inPath: Bool, hasAddress: Bool, mediaValid: Bool) -> Bool {
        if kind == .usbEthernet {
            return isUp || inPath || hasAddress || mediaValid
        }
        return isUp || inPath || hasAddress
    }
}

struct InterfaceCandidate: Equatable, Sendable {
    var name: String
    var kind: InterfaceKind
    var isPluggedIn: Bool
    var hasGlobalIPv4: Bool
    var isDefaultPath: Bool
}

enum InterfaceChooser {
    /// An explicit pin wins while that interface still exists.
    /// Otherwise a plugged-in USB Ethernet adapter wins, then the default route.
    static func resolve(candidates: [InterfaceCandidate], pinnedName: String?) -> String? {
        if let pinnedName, candidates.contains(where: { $0.name == pinnedName }) {
            return pinnedName
        }
        let dongles = candidates.filter { $0.kind == .usbEthernet && $0.isPluggedIn }
        if let dongle = bestDongle(dongles) {
            return dongle
        }
        if let path = candidates.first(where: \.isDefaultPath) {
            return path.name
        }
        if let addressed = candidates.first(where: \.hasGlobalIPv4) {
            return addressed.name
        }
        return candidates.first?.name
    }

    private static func bestDongle(_ dongles: [InterfaceCandidate]) -> String? {
        let ranked = dongles.sorted { lhs, rhs in
            if lhs.hasGlobalIPv4 != rhs.hasGlobalIPv4 { return lhs.hasGlobalIPv4 }
            if lhs.isDefaultPath != rhs.isDefaultPath { return lhs.isDefaultPath }
            return lhs.name < rhs.name
        }
        return ranked.first?.name
    }
}

enum InterfaceKindResolver {
    /// Positive identification wins. A bare `en2` is not treated as Ethernet,
    /// because iOS does not promise BSD names.
    static func resolve(
        pathKind: InterfaceKind?,
        catalogKind: InterfaceKind?,
        mediaKind: InterfaceKind?,
        bsdName: String
    ) -> InterfaceKind {
        if let pathKind, pathKind != .other { return pathKind }
        if let catalogKind, catalogKind != .other { return catalogKind }
        if let mediaKind, mediaKind != .other { return mediaKind }
        if bsdName.hasPrefix("pdp_ip") { return .cellular }
        if bsdName == "en0" { return .wifi }
        return .other
    }
}

enum InterfaceNaming {
    static func displayName(kind: InterfaceKind, localized: String?, bsdName: String) -> String {
        let cleaned = localized?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let generic = cleaned.isEmpty || cleaned == bsdName
        switch kind {
        case .usbEthernet:
            if generic || cleaned == "Ethernet" { return "USB Ethernet" }
            return cleaned
        case .wifi:
            if generic || cleaned == "Ethernet" { return "Wi-Fi" }
            return cleaned
        case .cellular:
            if generic { return "Cellular" }
            return cleaned
        case .other:
            return generic ? bsdName : cleaned
        }
    }
}

enum InterfaceOrdering {
    static func comesBefore(_ lhs: LocalInterface, _ rhs: LocalInterface) -> Bool {
        let left = rank(lhs.kind)
        let right = rank(rhs.kind)
        if left != right { return left < right }
        if lhs.hasGlobalIPv4 != rhs.hasGlobalIPv4 { return lhs.hasGlobalIPv4 }
        return lhs.bsdName.localizedCaseInsensitiveCompare(rhs.bsdName) == .orderedAscending
    }

    static func rank(_ kind: InterfaceKind) -> Int {
        switch kind {
        case .usbEthernet: return 0
        case .wifi: return 1
        case .cellular: return 2
        case .other: return 3
        }
    }
}

enum NeighborFilter {
    static func isUseful(ip: String, mac: String) -> Bool {
        if ip.isEmpty || mac.isEmpty { return false }
        if ip.hasPrefix("224.") || ip.hasPrefix("239.") || ip.hasSuffix(".255") { return false }
        if mac == "00:00:00:00:00:00" || mac.contains("INCOMPLETE") { return false }
        return true
    }

    static func matching(_ neighbors: [NeighborDevice], interface: LocalInterface) -> [NeighborDevice] {
        neighbors.filter { neighbor in
            if !neighbor.iface.isEmpty {
                return neighbor.iface == interface.bsdName
            }
            return contains(neighbor.ip, interface: interface)
        }
    }

    static func contains(_ ip: String, interface: LocalInterface) -> Bool {
        guard
            let prefix = interface.prefixLength,
            let address = IPv4.parse(ip),
            let network = interface.subnet.flatMap({ IPv4.parse($0.networkAddress) })
        else { return false }
        if prefix == 0 { return true }
        let mask: UInt32 = prefix == 32 ? .max : UInt32.max << (32 - prefix)
        return (address & mask) == (network & mask)
    }
}

enum SelectionCaption {
    static func text(pinnedName: String?, interfaceNames: [String], selectedKind: InterfaceKind?) -> String {
        if let pinnedName, !interfaceNames.contains(pinnedName) {
            return "Waiting for \(pinnedName). Showing another interface until it returns."
        }
        if pinnedName == nil, selectedKind == .usbEthernet {
            return "Automatic · USB Ethernet is connected"
        }
        if pinnedName == nil {
            return "Automatic"
        }
        return "Pinned"
    }
}

enum GatewayPicker {
    static func choose(
        routeGateway: String?,
        serviceGateway: String?,
        scopedGateways: [String],
        interfaceIsOnScopedPath: Bool,
        isPrimary: Bool,
        anyGateways: [String],
        globalRouter: String
    ) -> String {
        if let route = usable(routeGateway) { return route }
        if let service = usable(serviceGateway) { return service }
        if interfaceIsOnScopedPath, let scoped = firstUsable(scopedGateways) { return scoped }
        if isPrimary, let any = firstUsable(anyGateways) { return any }
        if isPrimary, let global = usable(globalRouter) { return global }
        return ""
    }

    static func firstUsable(_ gateways: [String]) -> String? {
        let cleaned = gateways.compactMap { usable($0) }
        if let global = cleaned.first(where: { !isLinkLocal($0) }) {
            return global
        }
        return cleaned.first
    }

    static func usable(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "0.0.0.0" || trimmed == "::" { return nil }
        return trimmed
    }

    static func isLinkLocal(_ value: String) -> Bool {
        value.hasPrefix("169.254.") || value.lowercased().hasPrefix("fe80:")
    }
}

enum ScopedPathMembership {
    static func contains(name: String, interfaces: [String], gateways: [String]) -> Bool {
        if interfaces.contains(name) { return true }
        return interfaces.isEmpty && !gateways.isEmpty
    }
}

enum DNSPicker {
    static func choose(serviceServers: [String], isPrimary: Bool, globalServers: [String]) -> [String] {
        let scoped = serviceServers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !scoped.isEmpty { return scoped }
        guard isPrimary else { return [] }
        return globalServers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
