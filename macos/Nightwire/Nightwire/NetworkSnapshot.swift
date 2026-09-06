import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

enum IpConfigurationType: String, Sendable {
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

struct LocalInterface: Identifiable, Equatable, Sendable {
    var id: String { bsdName }
    let bsdName: String
    let displayName: String
    let ipv4: String
    let cidr: String
    let mac: String
    let gateway: String
    let dnsServers: [String]
    let configuration: IpConfigurationType
    let linkSpeedBps: UInt64
    let isPrimary: Bool
    let wifiSSID: String?
    let wifiBSSID: String?
    let wifiChannel: String?
    let wifiBand: String?
    let wifiPHY: String?
    let wifiRSSI: String?
    let subnet: SubnetInfo?
    let hardwarePort: String?
    let serviceRank: Int?
    let dhcpLeaseObtained: String?
    let dhcpLeaseExpires: String?
    let dhcpServer: String?
    let rxBytes: UInt64
    let txBytes: UInt64

    var dnsText: String {
        dnsServers.isEmpty ? "None" : dnsServers.joined(separator: ", ")
    }

    var linkSpeedText: String {
        Self.formatSpeed(linkSpeedBps)
    }

    var title: String {
        displayName == bsdName ? bsdName : "\(displayName)  ·  \(bsdName)"
    }

    static func formatSpeed(_ bps: UInt64) -> String {
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

struct ThroughputPoint: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let downBps: Double
    let upBps: Double

    init(id: UUID = UUID(), timestamp: Date = Date(), downBps: Double, upBps: Double) {
        self.id = id
        self.timestamp = timestamp
        self.downBps = downBps
        self.upBps = upBps
    }
}

struct NetworkSnapshot: Equatable, Sendable {
    var interfaces: [LocalInterface]
    var publicIP: String?
    var neighbors: [NeighborDevice]

    var primary: LocalInterface? {
        interfaces.first(where: \.isPrimary) ?? interfaces.first
    }
}

enum SubnetCalculator {
    static func calculate(ip: String, prefix: Int) -> SubnetInfo? {
        guard prefix >= 0, prefix <= 32, let value = ipv4ToUInt32(ip) else { return nil }
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
            networkAddress: uInt32ToIPv4(network),
            broadcastAddress: uInt32ToIPv4(broadcast),
            firstHost: uInt32ToIPv4(first),
            lastHost: uInt32ToIPv4(last),
            usableHosts: usable
        )
    }

    private static func ipv4ToUInt32(_ ip: String) -> UInt32? {
        var addr = in_addr()
        guard inet_pton(AF_INET, ip, &addr) == 1 else { return nil }
        return UInt32(bigEndian: addr.s_addr)
    }

    private static func uInt32ToIPv4(_ value: UInt32) -> String {
        var addr = in_addr(s_addr: value.bigEndian)
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buffer)
    }
}

enum NetworkInterfaceReader {
    private static let skippedPrefixes = [
        "lo", "awdl", "llw", "utun", "gif", "stf", "p2p", "ap1", "ipsec", "dummy", "vmnet", "vmenet"
    ]

    static func read() -> [LocalInterface] {
        let global = readGlobalState()
        let methods = readConfigMethods()
        let names = readFriendlyNames()
        let wifiByBSD = readWifiDetails()
        let ranks = readServiceRanks()
        let ports = Dictionary(uniqueKeysWithValues: NetworkConfigurator.hardwarePorts().map { ($0.device, $0.port) })
        let addrs = collectAddresses()

        var results: [LocalInterface] = []
        for (bsd, info) in addrs {
            if shouldSkip(bsd) { continue }
            if info.ip.hasPrefix("169.254.") { continue }

            let prefix = info.prefix
            let gateway = global.gateways[bsd] ?? (global.primaryBSD == bsd ? global.router : "")
            let dns = global.dnsByBSD[bsd] ?? global.dns
            let wifi = wifiByBSD[bsd]
            let lease = methods[bsd] == .dhcp ? DHCPLeaseReader.read(bsd: bsd) : DHCPLeaseInfo()
            results.append(
                LocalInterface(
                    bsdName: bsd,
                    displayName: names[bsd] ?? friendlyFallback(bsd, wifi: wifi),
                    ipv4: info.ip,
                    cidr: "\(info.ip)/\(prefix)",
                    mac: info.mac,
                    gateway: gateway,
                    dnsServers: dns,
                    configuration: methods[bsd] ?? .unknown,
                    linkSpeedBps: info.speed,
                    isPrimary: false,
                    wifiSSID: wifi?.ssid,
                    wifiBSSID: wifi?.bssid,
                    wifiChannel: wifi?.channel,
                    wifiBand: wifi?.band,
                    wifiPHY: wifi?.phy,
                    wifiRSSI: wifi?.rssi,
                    subnet: SubnetCalculator.calculate(ip: info.ip, prefix: prefix),
                    hardwarePort: ports[bsd],
                    serviceRank: ranks[bsd],
                    dhcpLeaseObtained: lease.obtained,
                    dhcpLeaseExpires: lease.expires,
                    dhcpServer: lease.server,
                    rxBytes: info.rx,
                    txBytes: info.tx
                )
            )
        }

        results.sort { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        if let primaryBSD = global.primaryBSD,
           let index = results.firstIndex(where: { $0.bsdName == primaryBSD }) {
            results[index] = withPrimary(results[index], true)
        } else if !results.isEmpty {
            results[0] = withPrimary(results[0], true)
        }

        return results.sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func withPrimary(_ iface: LocalInterface, _ isPrimary: Bool) -> LocalInterface {
        LocalInterface(
            bsdName: iface.bsdName,
            displayName: iface.displayName,
            ipv4: iface.ipv4,
            cidr: iface.cidr,
            mac: iface.mac,
            gateway: iface.gateway,
            dnsServers: iface.dnsServers,
            configuration: iface.configuration,
            linkSpeedBps: iface.linkSpeedBps,
            isPrimary: isPrimary,
            wifiSSID: iface.wifiSSID,
            wifiBSSID: iface.wifiBSSID,
            wifiChannel: iface.wifiChannel,
            wifiBand: iface.wifiBand,
            wifiPHY: iface.wifiPHY,
            wifiRSSI: iface.wifiRSSI,
            subnet: iface.subnet,
            hardwarePort: iface.hardwarePort,
            serviceRank: iface.serviceRank,
            dhcpLeaseObtained: iface.dhcpLeaseObtained,
            dhcpLeaseExpires: iface.dhcpLeaseExpires,
            dhcpServer: iface.dhcpServer,
            rxBytes: iface.rxBytes,
            txBytes: iface.txBytes
        )
    }

    private static func shouldSkip(_ name: String) -> Bool {
        skippedPrefixes.contains { name == $0 || name.hasPrefix($0) }
    }

    private static func friendlyFallback(_ bsd: String, wifi: WifiDetails?) -> String {
        if wifi != nil { return "Wi-Fi" }
        if bsd.hasPrefix("en") { return "Ethernet" }
        return bsd
    }

    private struct AddressInfo {
        var ip: String
        var prefix: Int
        var mac: String
        var speed: UInt64
        var rx: UInt64
        var tx: UInt64
    }

    private static func collectAddresses() -> [String: AddressInfo] {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return [:] }
        defer { freeifaddrs(first) }

        var ipv4: [String: (ip: String, prefix: Int)] = [:]
        var macs: [String: String] = [:]
        var speeds: [String: UInt64] = [:]
        var rx: [String: UInt64] = [:]
        var tx: [String: UInt64] = [:]

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            let name = String(cString: ifa.pointee.ifa_name)
            let flags = Int32(ifa.pointee.ifa_flags)
            if flags & IFF_LOOPBACK != 0 || flags & IFF_UP == 0 {
                cursor = ifa.pointee.ifa_next
                continue
            }

            if let addr = ifa.pointee.ifa_addr {
                switch Int32(addr.pointee.sa_family) {
                case AF_INET:
                    if let ip = ipv4String(addr), !ip.hasPrefix("127.") {
                        let prefix = prefixLength(ifa.pointee.ifa_netmask)
                        ipv4[name] = (ip, prefix)
                    }
                case AF_LINK:
                    if let mac = macString(addr) {
                        macs[name] = mac
                    }
                    if let data = ifa.pointee.ifa_data {
                        let stats = data.assumingMemoryBound(to: if_data.self).pointee
                        if stats.ifi_baudrate > 0 {
                            speeds[name] = UInt64(stats.ifi_baudrate)
                        }
                        rx[name] = UInt64(stats.ifi_ibytes)
                        tx[name] = UInt64(stats.ifi_obytes)
                    }
                default:
                    break
                }
            }
            cursor = ifa.pointee.ifa_next
        }

        var combined: [String: AddressInfo] = [:]
        for (name, pair) in ipv4 {
            combined[name] = AddressInfo(
                ip: pair.ip,
                prefix: pair.prefix,
                mac: macs[name] ?? "—",
                speed: speeds[name] ?? 0,
                rx: rx[name] ?? 0,
                tx: tx[name] ?? 0
            )
        }
        return combined
    }

    private static func ipv4String(_ addr: UnsafeMutablePointer<sockaddr>) -> String? {
        addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
            var address = sin.pointee.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: buffer)
        }
    }

    private static func prefixLength(_ netmask: UnsafeMutablePointer<sockaddr>?) -> Int {
        guard let netmask else { return 24 }
        return netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
            Int(UInt32(bigEndian: sin.pointee.sin_addr.s_addr).nonzeroBitCount)
        }
    }

    private static func macString(_ addr: UnsafeMutablePointer<sockaddr>) -> String? {
        addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { sdl in
            let length = Int(sdl.pointee.sdl_alen)
            guard length == 6 else { return nil }
            let offset = Int(sdl.pointee.sdl_nlen)
            return withUnsafePointer(to: sdl.pointee.sdl_data) { dataPtr in
                let bytes = UnsafeRawPointer(dataPtr).advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                return (0..<6).map { String(format: "%02X", bytes[$0]) }.joined(separator: ":")
            }
        }
    }

    private struct GlobalState {
        var primaryBSD: String?
        var router: String
        var dns: [String]
        var gateways: [String: String]
        var dnsByBSD: [String: [String]]
    }

    private static func readGlobalState() -> GlobalState {
        var state = GlobalState(primaryBSD: nil, router: "", dns: [], gateways: [:], dnsByBSD: [:])
        guard let store = SCDynamicStoreCreate(nil, "Nightwire" as CFString, nil, nil) else {
            return state
        }

        if let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
            state.primaryBSD = ipv4["PrimaryInterface"] as? String
            state.router = ipv4["Router"] as? String ?? ""
        }

        if let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
           let servers = dns["ServerAddresses"] as? [String] {
            state.dns = servers
        }

        if let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/[^/]+/IPv4" as CFString) as? [String] {
            for key in keys {
                guard let dict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] else { continue }
                let bsd = dict["InterfaceName"] as? String
                let router = dict["Router"] as? String ?? (dict["Router"] as? [String])?.first
                if let bsd, let router, !router.isEmpty {
                    state.gateways[bsd] = router
                }

                let serviceID = key
                    .replacingOccurrences(of: "State:/Network/Service/", with: "")
                    .replacingOccurrences(of: "/IPv4", with: "")
                if let bsd,
                   let dnsDict = SCDynamicStoreCopyValue(
                    store,
                    "State:/Network/Service/\(serviceID)/DNS" as CFString
                   ) as? [String: Any],
                   let servers = dnsDict["ServerAddresses"] as? [String],
                   !servers.isEmpty {
                    state.dnsByBSD[bsd] = servers
                }
            }
        }

        return state
    }

    private static func readConfigMethods() -> [String: IpConfigurationType] {
        var methods: [String: IpConfigurationType] = [:]
        guard let prefs = SCPreferencesCreate(nil, "Nightwire" as CFString, nil),
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService]
        else {
            return methods
        }

        for service in services {
            guard let iface = SCNetworkServiceGetInterface(service),
                  let bsd = SCNetworkInterfaceGetBSDName(iface) as String?,
                  let proto = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeIPv4),
                  let config = SCNetworkProtocolGetConfiguration(proto) as? [String: Any],
                  let method = config[kSCPropNetIPv4ConfigMethod as String] as? String
            else {
                continue
            }

            let lowered = method.lowercased()
            if lowered.contains("dhcp") || lowered.contains("bootp") || lowered.contains("inform") {
                methods[bsd] = .dhcp
            } else if lowered.contains("manual") {
                methods[bsd] = .staticConfig
            } else {
                methods[bsd] = methods[bsd] ?? .unknown
            }
        }
        return methods
    }

    private static func readFriendlyNames() -> [String: String] {
        var names: [String: String] = [:]
        guard let prefs = SCPreferencesCreate(nil, "Nightwire" as CFString, nil),
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService]
        else {
            return names
        }

        for service in services {
            guard let iface = SCNetworkServiceGetInterface(service),
                  let bsd = SCNetworkInterfaceGetBSDName(iface) as String?
            else {
                continue
            }
            if let localized = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String?, !localized.isEmpty {
                names[bsd] = localized
            } else if let serviceName = SCNetworkServiceGetName(service) as String?, !serviceName.isEmpty {
                names[bsd] = serviceName
            }
        }
        return names
    }

    private struct WifiDetails {
        var ssid: String?
        var bssid: String?
        var channel: String?
        var band: String?
        var phy: String?
        var rssi: String?
    }

    private static func readWifiDetails() -> [String: WifiDetails] {
        var result: [String: WifiDetails] = [:]
        let client = CWWiFiClient.shared()
        let interfaces = client.interfaces() ?? []
        for iface in interfaces {
            guard let bsd = iface.interfaceName else { continue }
            var details = WifiDetails()
            details.ssid = iface.ssid()
            details.bssid = iface.bssid()
            if let channel = iface.wlanChannel() {
                details.channel = String(channel.channelNumber)
                details.band = bandName(channel.channelBand)
            }
            details.phy = phyName(iface.activePHYMode())
            let rssi = iface.rssiValue()
            if rssi != 0 {
                details.rssi = "\(rssi) dBm"
            }
            result[bsd] = details
        }
        return result
    }

    private static func bandName(_ band: CWChannelBand) -> String {
        switch band {
        case .band2GHz: return "2.4 GHz"
        case .band5GHz: return "5 GHz"
        case .band6GHz: return "6 GHz"
        default: return "Unknown"
        }
    }

    private static func phyName(_ mode: CWPHYMode) -> String {
        switch mode {
        case .mode11a: return "802.11a"
        case .mode11b: return "802.11b"
        case .mode11g: return "802.11g"
        case .mode11n: return "802.11n"
        case .mode11ac: return "802.11ac"
        case .mode11ax: return "802.11ax"
        default: return "Unknown"
        }
    }

    private static func readServiceRanks() -> [String: Int] {
        var ranks: [String: Int] = [:]
        guard let prefs = SCPreferencesCreate(nil, "NightwireRank" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(prefs),
              let order = SCNetworkSetGetServiceOrder(set) as? [CFString],
              let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService]
        else {
            return ranks
        }

        var bsdByService: [String: String] = [:]
        for service in services {
            guard let id = SCNetworkServiceGetServiceID(service) as String?,
                  let iface = SCNetworkServiceGetInterface(service),
                  let bsd = SCNetworkInterfaceGetBSDName(iface) as String?
            else { continue }
            bsdByService[id] = bsd
        }

        for (index, serviceID) in order.enumerated() {
            if let bsd = bsdByService[serviceID as String] {
                ranks[bsd] = index + 1
            }
        }
        return ranks
    }
}
