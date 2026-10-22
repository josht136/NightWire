import XCTest
@testable import Nightwire

final class NetworkMathTests: XCTestCase {
    func testSubnet24() {
        let info = SubnetCalculator.calculate(ip: "192.168.4.20", prefix: 24)
        XCTAssertEqual(info?.networkAddress, "192.168.4.0")
        XCTAssertEqual(info?.broadcastAddress, "192.168.4.255")
        XCTAssertEqual(info?.firstHost, "192.168.4.1")
        XCTAssertEqual(info?.lastHost, "192.168.4.254")
        XCTAssertEqual(info?.usableHosts, 254)
        XCTAssertEqual(info?.hostRange, "192.168.4.1 – 192.168.4.254")
    }

    func testSubnet30AndPointToPoint() {
        let slash30 = SubnetCalculator.calculate(ip: "10.0.0.5", prefix: 30)
        XCTAssertEqual(slash30?.networkAddress, "10.0.0.4")
        XCTAssertEqual(slash30?.broadcastAddress, "10.0.0.7")
        XCTAssertEqual(slash30?.firstHost, "10.0.0.5")
        XCTAssertEqual(slash30?.lastHost, "10.0.0.6")
        XCTAssertEqual(slash30?.usableHosts, 2)

        let slash31 = SubnetCalculator.calculate(ip: "10.0.0.0", prefix: 31)
        XCTAssertEqual(slash31?.networkAddress, "10.0.0.0")
        XCTAssertEqual(slash31?.broadcastAddress, "10.0.0.1")
        XCTAssertEqual(slash31?.usableHosts, 2)

        let slash32 = SubnetCalculator.calculate(ip: "10.0.0.5", prefix: 32)
        XCTAssertEqual(slash32?.networkAddress, "10.0.0.5")
        XCTAssertEqual(slash32?.broadcastAddress, "10.0.0.5")
        XCTAssertEqual(slash32?.usableHosts, 1)
    }

    func testSubnetRejectsGarbage() {
        XCTAssertNil(SubnetCalculator.calculate(ip: "192.168.1.1", prefix: 33))
        XCTAssertNil(SubnetCalculator.calculate(ip: "nope", prefix: 24))
    }

    func testLinkSpeed() {
        XCTAssertEqual(LinkSpeed.bitsPerSecond(subtype: 16), 1_000_000_000)
        XCTAssertEqual(LinkSpeed.bitsPerSecond(subtype: 22), 2_500_000_000)
        XCTAssertEqual(LinkSpeed.bitsPerSecond(subtype: 21), 10_000_000_000)
        XCTAssertEqual(LinkSpeed.bitsPerSecond(subtype: 6), 100_000_000)
        XCTAssertEqual(LinkSpeed.bitsPerSecond(subtype: 0), 0)
        XCTAssertEqual(LinkSpeed.format(10_000_000_000), "10 Gbps")
        XCTAssertEqual(LinkSpeed.format(100_000_000), "100 Mbps")
        XCTAssertEqual(LinkSpeed.format(10_000_000), "10 Mbps")
        XCTAssertEqual(LinkSpeed.format(500), "500 bps")
        XCTAssertEqual(LinkSpeed.format(0), "Unknown")
        XCTAssertTrue(LinkSpeed.format(2_500_000_000).hasSuffix("Gbps"))
        XCTAssertTrue(LinkSpeed.format(1_000_000_000).hasPrefix("1"))
    }

    func testGatewayPicker() {
        XCTAssertEqual(
            GatewayPicker.choose(
                routeGateway: "192.168.4.1",
                serviceGateway: "10.0.0.1",
                scopedGateways: ["10.1.1.1"],
                interfaceIsOnScopedPath: true,
                isPrimary: false,
                anyGateways: ["8.8.8.8"],
                globalRouter: "1.1.1.1"
            ),
            "192.168.4.1"
        )
        XCTAssertEqual(
            GatewayPicker.choose(
                routeGateway: nil,
                serviceGateway: nil,
                scopedGateways: ["169.254.1.1", "192.168.4.1"],
                interfaceIsOnScopedPath: true,
                isPrimary: false,
                anyGateways: ["10.0.0.1"],
                globalRouter: "10.0.0.1"
            ),
            "192.168.4.1"
        )
        XCTAssertEqual(
            GatewayPicker.choose(
                routeGateway: nil,
                serviceGateway: "",
                scopedGateways: [],
                interfaceIsOnScopedPath: false,
                isPrimary: false,
                anyGateways: ["192.168.1.1"],
                globalRouter: "192.168.1.1"
            ),
            ""
        )
        XCTAssertEqual(
            GatewayPicker.choose(
                routeGateway: "0.0.0.0",
                serviceGateway: nil,
                scopedGateways: [],
                interfaceIsOnScopedPath: false,
                isPrimary: true,
                anyGateways: [],
                globalRouter: "192.168.0.1"
            ),
            "192.168.0.1"
        )
    }

    func testDNSPickerDoesNotLeakThePrimaryResolver() {
        XCTAssertEqual(
            DNSPicker.choose(serviceServers: ["  "], isPrimary: false, globalServers: ["1.1.1.1"]),
            []
        )
        XCTAssertEqual(
            DNSPicker.choose(serviceServers: [], isPrimary: true, globalServers: ["1.1.1.1", " "]),
            ["1.1.1.1"]
        )
        XCTAssertEqual(
            DNSPicker.choose(serviceServers: ["192.168.4.1"], isPrimary: false, globalServers: ["8.8.8.8"]),
            ["192.168.4.1"]
        )
    }

    func testScopedPathMembership() {
        XCTAssertTrue(ScopedPathMembership.contains(name: "en2", interfaces: ["en2"], gateways: []))
        XCTAssertTrue(ScopedPathMembership.contains(name: "en2", interfaces: [], gateways: ["192.168.4.1"]))
        XCTAssertFalse(ScopedPathMembership.contains(name: "en2", interfaces: ["en3"], gateways: ["192.168.4.1"]))
        XCTAssertFalse(ScopedPathMembership.contains(name: "en2", interfaces: [], gateways: []))
    }

    func testNeighborFilter() {
        let ethernet = LocalInterface(
            bsdName: "en2",
            displayName: "USB Ethernet",
            kind: .usbEthernet,
            ipv4: "192.168.4.20",
            prefixLength: 24,
            cidr: "192.168.4.20/24",
            subnet: SubnetCalculator.calculate(ip: "192.168.4.20", prefix: 24)
        )
        let neighbors = [
            NeighborDevice(ip: "192.168.4.1", mac: "00:E0:4C:00:00:01", iface: "en2", vendor: "Realtek"),
            NeighborDevice(ip: "192.168.1.1", mac: "00:E0:4C:00:00:02", iface: "en0", vendor: "Realtek"),
            NeighborDevice(ip: "192.168.4.40", mac: "00:E0:4C:00:00:03", iface: "", vendor: "Realtek"),
            NeighborDevice(ip: "224.0.0.1", mac: "01:00:5E:00:00:01", iface: "en2", vendor: "Unknown"),
            NeighborDevice(ip: "192.168.4.255", mac: "FF:FF:FF:FF:FF:FF", iface: "en2", vendor: "Unknown")
        ]
        XCTAssertFalse(NeighborFilter.isUseful(ip: "224.0.0.1", mac: "01:00:5E:00:00:01"))
        XCTAssertFalse(NeighborFilter.isUseful(ip: "192.168.4.255", mac: "FF:FF:FF:FF:FF:FF"))
        let visible = NeighborFilter.matching(neighbors.filter { NeighborFilter.isUseful(ip: $0.ip, mac: $0.mac) }, interface: ethernet)
        XCTAssertEqual(visible.map(\.ip), ["192.168.4.1", "192.168.4.40"])
    }

    func testMACAddressAndVendor() {
        XCTAssertNil(MACAddress.normalize("00:00:00:00:00:00"))
        XCTAssertEqual(MACAddress.normalize("00-e0-4c-10-20-30"), "00:E0:4C:10:20:30")
        XCTAssertEqual(MACVendor.lookup("00:E0:4C:10:20:30"), "Realtek")
        XCTAssertEqual(MACVendor.lookup("12:34:56:78:9A:BC"), "Unknown")
    }

    func testEthernetDetailRowsMatchTheMacDetailsWindow() {
        let iface = LocalInterface(
            bsdName: "en2",
            displayName: "USB Ethernet",
            kind: .usbEthernet,
            ipv4: "192.168.4.20",
            prefixLength: 24,
            cidr: "192.168.4.20/24",
            mac: "00:E0:4C:10:20:30",
            gateway: "192.168.4.1",
            dnsServers: ["192.168.4.1"],
            configuration: .dhcp,
            linkSpeedBps: 1_000_000_000,
            isPrimary: true,
            isPluggedIn: true,
            hasLink: true,
            hasGlobalIPv4: true,
            subnet: SubnetCalculator.calculate(ip: "192.168.4.20", prefix: 24),
            serviceRank: 1,
            dhcpLeaseObtained: "today",
            dhcpLeaseExpires: "tomorrow",
            dhcpServer: "192.168.4.1"
        )
        let titles = DetailRows.make(iface: iface, publicIPText: "203.0.113.10").map(\.title)
        XCTAssertEqual(
            titles,
            [
                "IP address", "CIDR", "MAC", "Link speed", "Gateway", "DNS",
                "Network", "Broadcast", "Host range", "Usable hosts",
                "Service order", "DHCP obtained", "DHCP expires", "DHCP server",
                "Public IP"
            ]
        )
        let pasted = DetailRows.copyAll(iface: iface, publicIP: "203.0.113.10")
        XCTAssertTrue(pasted.contains("Interface: USB Ethernet  ·  en2"))
        XCTAssertTrue(pasted.contains("Config: DHCP"))
        XCTAssertTrue(pasted.contains("Gateway: 192.168.4.1"))
        XCTAssertTrue(pasted.contains("Public IP: 203.0.113.10"))
        XCTAssertTrue(pasted.contains("Service order: 1"))
    }

    func testWiFiRowsStayVisibleWhenIOSHidesRadioDetails() {
        let iface = LocalInterface(
            bsdName: "en0",
            displayName: "Wi-Fi",
            kind: .wifi,
            ipv4: "192.168.1.20",
            prefixLength: 24,
            cidr: "192.168.1.20/24",
            wifiSSID: "Nightwire",
            wifiRSSI: "70%"
        )
        let rows = DetailRows.make(iface: iface, publicIPText: "…")
        let byTitle = Dictionary(uniqueKeysWithValues: rows.map { ($0.title, $0) })
        XCTAssertEqual(byTitle["SSID"]?.value, "Nightwire")
        XCTAssertEqual(byTitle["Signal"]?.value, "70%")
        XCTAssertEqual(byTitle["Channel"]?.value, "Unavailable")
        XCTAssertEqual(byTitle["Band"]?.value, "Unavailable")
        XCTAssertEqual(byTitle["Radio"]?.value, "Unavailable")
        XCTAssertFalse(DetailRows.isCopyable(byTitle["Channel"]?.copyValue ?? ""))
        XCTAssertEqual(rows.last?.title, "Public IP")
        XCTAssertNotNil(DetailRows.wifiFootnote(for: iface))
        XCTAssertNil(DetailRows.wifiFootnote(for: LocalInterface(bsdName: "en2", displayName: "USB Ethernet", kind: .usbEthernet)))
    }
}
