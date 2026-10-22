import Darwin
import Foundation

enum NetworkSnapshotBuilder {
    struct BuiltSnapshot: Sendable {
        var interfaces: [LocalInterface]
        var neighbors: [NeighborDevice]
        var neighborsUnavailable: Bool
    }

    static func build(wifi: WiFiSnapshot, paths: PathSnapshot) -> BuiltSnapshot {
        let addresses = collectAddresses()
        let routeRead = RouteTable.read()
        let records = routeRead.records
        let globalDNS = RouteTable.systemDNS()

        var gatewayByName: [String: String] = [:]
        for record in records where record.isDefault && !record.ifname.isEmpty {
            if gatewayByName[record.ifname] == nil, let gateway = GatewayPicker.usable(record.gateway) {
                gatewayByName[record.ifname] = gateway
            }
        }

        let pathNames = Set(
            paths.anyInterfaces
                + paths.wiredInterfaces
                + paths.wifiInterfaces
                + paths.cellularInterfaces
        )
        var names = Set(addresses.keys)
        names.formUnion(pathNames)
        names.formUnion(paths.kindsByName.keys)

        struct Draft {
            var name: String
            var kind: InterfaceKind
            var facts: AddressFacts
            var media: RouteTable.Media
        }

        var drafts: [Draft] = []
        for name in names where !shouldSkip(name) {
            let facts = addresses[name] ?? AddressFacts()
            let media = RouteTable.media(for: name)
            let kind = InterfaceKindResolver.resolve(
                pathKind: paths.kindsByName[name],
                catalogKind: nil,
                mediaKind: mediaKind(media),
                bsdName: name
            )
            guard kind != .other else { continue }
            let hasAddress = !facts.ipv4.isEmpty
            let plugged = PlugState.isPluggedIn(
                kind: kind,
                isUp: facts.isUp,
                inPath: pathNames.contains(name),
                hasAddress: hasAddress,
                mediaValid: media.valid
            )
            guard plugged else { continue }
            drafts.append(Draft(name: name, kind: kind, facts: facts, media: media))
        }

        let visibleNames = Set(drafts.map(\.name))
        let primary = paths.anyInterfaces.first(where: { visibleNames.contains($0) })
            ?? records.first(where: { $0.isDefault && visibleNames.contains($0.ifname) })?.ifname

        var interfaces: [LocalInterface] = []
        interfaces.reserveCapacity(drafts.count)
        for draft in drafts {
            let name = draft.name
            let facts = draft.facts
            let isPrimary = name == primary
            let hasGlobal = !facts.ipv4.isEmpty && !facts.ipv4.hasPrefix("169.254.")
            let scoped = scopedPath(kind: draft.kind, paths: paths)
            let gateway = GatewayPicker.choose(
                routeGateway: gatewayByName[name],
                serviceGateway: nil,
                scopedGateways: scoped.gateways,
                interfaceIsOnScopedPath: ScopedPathMembership.contains(
                    name: name,
                    interfaces: scoped.interfaces,
                    gateways: scoped.gateways
                ),
                isPrimary: isPrimary,
                anyGateways: paths.anyGateways,
                globalRouter: ""
            )
            let dns = DNSPicker.choose(
                serviceServers: [],
                isPrimary: isPrimary,
                globalServers: globalDNS
            )
            let prefix = facts.prefix
            let cidr: String
            if facts.ipv4.isEmpty {
                cidr = "None"
            } else if let prefix {
                cidr = "\(facts.ipv4)/\(prefix)"
            } else {
                cidr = facts.ipv4
            }
            let subnet = prefix.flatMap { SubnetCalculator.calculate(ip: facts.ipv4, prefix: $0) }
            let mac = MACAddress.normalize(facts.mac) ?? "—"
            let mappedSpeed = draft.media.valid ? LinkSpeed.bitsPerSecond(subtype: draft.media.subtype) : 0
            let speed = mappedSpeed > 0 ? mappedSpeed : facts.baudrate
            let hasLink = LinkState.hasLink(
                hasGlobalIPv4: hasGlobal,
                isRunning: facts.isRunning,
                mediaValid: draft.media.valid,
                mediaStatus: draft.media.status
            )
            interfaces.append(
                LocalInterface(
                    bsdName: name,
                    displayName: InterfaceNaming.displayName(
                        kind: draft.kind,
                        localized: nil,
                        bsdName: name
                    ),
                    kind: draft.kind,
                    ipv4: facts.ipv4,
                    prefixLength: prefix,
                    cidr: cidr,
                    mac: mac,
                    gateway: gateway,
                    dnsServers: dns,
                    configuration: .unknown,
                    linkSpeedBps: speed,
                    isPrimary: isPrimary,
                    isPluggedIn: true,
                    hasLink: hasLink,
                    hasGlobalIPv4: hasGlobal,
                    wifiSSID: draft.kind == .wifi ? wifi.ssid : nil,
                    wifiBSSID: draft.kind == .wifi ? wifi.bssid : nil,
                    wifiChannel: nil,
                    wifiBand: nil,
                    wifiPHY: nil,
                    wifiRSSI: draft.kind == .wifi ? wifi.signal : nil,
                    subnet: subnet,
                    serviceRank: nil,
                    dhcpLeaseObtained: nil,
                    dhcpLeaseExpires: nil,
                    dhcpServer: nil
                )
            )
        }
        interfaces.sort(by: InterfaceOrdering.comesBefore)

        var neighbors: [NeighborDevice] = []
        var seen: Set<String> = []
        for record in records where record.isNeighbor {
            let mac = MACAddress.normalize(record.mac) ?? ""
            guard NeighborFilter.isUseful(ip: record.destination, mac: mac) else { continue }
            let device = NeighborDevice(
                ip: record.destination,
                mac: mac,
                iface: record.ifname,
                vendor: MACVendor.lookup(mac)
            )
            if seen.insert(device.id).inserted {
                neighbors.append(device)
            }
        }
        neighbors.sort { $0.ip.localizedStandardCompare($1.ip) == .orderedAscending }

        return BuiltSnapshot(
            interfaces: interfaces,
            neighbors: neighbors,
            neighborsUnavailable: routeRead.unavailable
        )
    }

    private static func scopedPath(kind: InterfaceKind, paths: PathSnapshot) -> (interfaces: [String], gateways: [String]) {
        switch kind {
        case .usbEthernet:
            return (paths.wiredInterfaces, paths.wiredGateways)
        case .wifi:
            return (paths.wifiInterfaces, paths.wifiGateways)
        case .cellular:
            return (paths.cellularInterfaces, paths.cellularGateways)
        case .other:
            return ([], [])
        }
    }

    private static func mediaKind(_ media: RouteTable.Media) -> InterfaceKind? {
        guard media.valid else { return nil }
        if media.type == 0x20 { return .usbEthernet }
        if media.type == 0x80 { return .wifi }
        return nil
    }

    private static func shouldSkip(_ name: String) -> Bool {
        NetworkSnapshotBuilderSkips.name(name)
    }
}

private struct AddressFacts {
    var ipv4 = ""
    var prefix: Int?
    var mac: String?
    var baudrate: UInt64 = 0
    var isUp = false
    var isRunning = false
}

private extension Result where Success == [RouteTable.Record], Failure == RouteTable.ReadFailure {
    var records: [RouteTable.Record] {
        switch self {
        case .success(let records):
            return records
        case .failure:
            return []
        }
    }

    var unavailable: Bool {
        if case .failure = self { return true }
        return false
    }
}

private func collectAddresses() -> [String: AddressFacts] {
    var result: [String: AddressFacts] = [:]
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return [:] }
    defer { freeifaddrs(first) }

    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    while let interface = cursor {
        let name = String(cString: interface.pointee.ifa_name)
        let flags = Int32(interface.pointee.ifa_flags)
        cursor = interface.pointee.ifa_next
        if NetworkSnapshotBuilderSkips.name(name) || flags & IFF_LOOPBACK != 0 {
            continue
        }

        var facts = result[name] ?? AddressFacts()
        facts.isUp = facts.isUp || (flags & IFF_UP) != 0
        facts.isRunning = facts.isRunning || (flags & IFF_RUNNING) != 0

        if let address = interface.pointee.ifa_addr {
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                if let ip = ipv4String(address), !ip.hasPrefix("127.") {
                    let prefix = prefixLength(interface.pointee.ifa_netmask)
                    let replace = facts.ipv4.isEmpty || (facts.ipv4.hasPrefix("169.254.") && !ip.hasPrefix("169.254."))
                    if replace {
                        facts.ipv4 = ip
                        facts.prefix = prefix
                    }
                }
            case AF_LINK:
                if facts.mac == nil {
                    facts.mac = macString(address)
                }
                if let data = interface.pointee.ifa_data {
                    let stats = data.assumingMemoryBound(to: if_data.self).pointee
                    if stats.ifi_baudrate > 0 {
                        facts.baudrate = UInt64(stats.ifi_baudrate)
                    }
                }
            default:
                break
            }
        }
        result[name] = facts
    }
    return result
}

/// Shared with the builder so the address walk and the name union use one skip list.
private enum NetworkSnapshotBuilderSkips {
    static func name(_ name: String) -> Bool {
        if name.isEmpty { return true }
        let prefixes = [
            "lo", "awdl", "llw", "utun", "gif", "stf", "p2p", "ap", "ipsec",
            "dummy", "vmnet", "vmenet", "bridge", "pktap", "anpi", "XHC"
        ]
        return prefixes.contains { name == $0 || name.hasPrefix($0) }
    }
}

private func ipv4String(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
    address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
        var value = sin.pointee.sin_addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &value, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            return nil
        }
        return String(cString: buffer)
    }
}

private func prefixLength(_ netmask: UnsafeMutablePointer<sockaddr>?) -> Int? {
    guard let netmask else { return nil }
    return netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
        Int(UInt32(bigEndian: sin.pointee.sin_addr.s_addr).nonzeroBitCount)
    }
}

private func macString(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
    address.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { link in
        let length = Int(link.pointee.sdl_alen)
        guard length == 6 else { return nil }
        let offset = Int(link.pointee.sdl_nlen)
        return withUnsafePointer(to: link.pointee.sdl_data) { dataPointer in
            let bytes = UnsafeRawPointer(dataPointer).advanced(by: offset).assumingMemoryBound(to: UInt8.self)
            return (0..<6).map { String(format: "%02X", bytes[$0]) }.joined(separator: ":")
        }
    }
}

