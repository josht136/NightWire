import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class NetworkStatusStore {
    static let pinKey = "nightwire.ios.pinnedInterface"

    var interfaces: [LocalInterface] = []
    var neighbors: [NeighborDevice] = []
    var neighborsUnavailable = false
    var publicIPText = "…"
    var copiedField: String?
    var pinnedName: String?
    var resolvedName: String?
    var hasLoaded = false
    var lastRefresh: Date?

    private var publicIP: String?
    private let pathWatch = PathWatch()
    private var pollTask: Task<Void, Never>?
    private var publicTask: Task<Void, Never>?
    private var copyReset: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshPending = false
    private var publicIPPending = false
    private var started = false
    private var lastPublicFetch = Date.distantPast
    private var lastPublicInterface: String?
    private var publicGeneration = UUID()
    private let ignoresSavedPin: Bool

    init(ignoresSavedPin: Bool = false) {
        self.ignoresSavedPin = ignoresSavedPin
        if !ignoresSavedPin {
            let saved = UserDefaults.standard.string(forKey: Self.pinKey)
            pinnedName = (saved?.isEmpty == false) ? saved : nil
        }
    }

    var selected: LocalInterface? {
        interfaces.first { $0.bsdName == resolvedName }
    }

    var visibleNeighbors: [NeighborDevice] {
        guard let selected else { return [] }
        return NeighborFilter.matching(neighbors, interface: selected)
    }

    var selectionCaption: String {
        SelectionCaption.text(
            pinnedName: pinnedName,
            interfaceNames: interfaces.map(\.bsdName),
            selectedKind: selected?.kind
        )
    }

    func start() {
        guard !started else {
            resumePolling()
            requestRefresh(publicIP: true)
            return
        }
        started = true
        pathWatch.start()
        pathWatch.onChange = { [weak self] in
            Task { @MainActor in
                self?.requestRefresh(publicIP: false)
            }
        }
        WiFiReader.shared.onChange = { [weak self] in
            self?.requestRefresh(publicIP: false)
        }
        requestRefresh(publicIP: true)
        resumePolling()
    }

    func pausePolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func resumePolling() {
        guard started, pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.requestRefresh(publicIP: false)
            }
        }
    }

    func refreshNow() async {
        requestRefresh(publicIP: true)
        while refreshPending || publicIPPending || refreshTask != nil {
            await refreshTask?.value
            if refreshTask == nil, !refreshPending, !publicIPPending {
                break
            }
        }
    }

    func pin(_ name: String?) {
        pinnedName = name
        if !ignoresSavedPin {
            if let name {
                UserDefaults.standard.set(name, forKey: Self.pinKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pinKey)
            }
        }
        applySelection(forcePublicIP: true)
        updateWiFiDemand()
    }

    func copy(_ value: String, field: String) {
        guard DetailRows.isCopyable(value) else { return }
        UIPasteboard.general.string = value
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        copiedField = field
        copyReset?.cancel()
        copyReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard let self, self.copiedField == field else { return }
            self.copiedField = nil
        }
    }

    func copyAll(for iface: LocalInterface) {
        copy(DetailRows.copyAll(iface: iface, publicIP: publicIP), field: "all")
    }

    private func requestRefresh(publicIP: Bool) {
        if publicIP { publicIPPending = true }
        refreshPending = true
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drainRefreshes()
            self.refreshTask = nil
            if self.refreshPending || self.publicIPPending {
                self.requestRefresh(publicIP: false)
            }
        }
    }

    private func drainRefreshes() async {
        while refreshPending || publicIPPending {
            let force = publicIPPending
            refreshPending = false
            publicIPPending = false
            await refreshLocal(forcePublicIP: force)
        }
    }

    private func refreshLocal(forcePublicIP: Bool) async {
        let wifi = WiFiReader.shared.snapshot
        let paths = pathWatch.snapshot()
        let built = await Task.detached(priority: .userInitiated) {
            NetworkSnapshotBuilder.build(wifi: wifi, paths: paths)
        }.value
        apply(built, forcePublicIP: forcePublicIP)
    }

    private func apply(_ built: NetworkSnapshotBuilder.BuiltSnapshot, forcePublicIP: Bool) {
        interfaces = built.interfaces
        neighbors = built.neighbors
        neighborsUnavailable = built.neighborsUnavailable
        lastRefresh = Date()
        hasLoaded = true
        applySelection(forcePublicIP: forcePublicIP)
        updateWiFiDemand()
    }

    private func applySelection(forcePublicIP: Bool) {
        let previous = resolvedName
        resolvedName = InterfaceChooser.resolve(
            candidates: interfaces.map(\.candidate),
            pinnedName: pinnedName
        )
        if resolvedName != previous {
            publicIP = nil
            publicIPText = resolvedName == nil ? "Unavailable" : "…"
            lastPublicInterface = nil
        }
        refreshPublicIP(force: forcePublicIP || resolvedName != previous)
    }

    private func refreshPublicIP(force: Bool) {
        guard let name = resolvedName else {
            publicTask?.cancel()
            publicIP = nil
            publicIPText = "Unavailable"
            return
        }
        let elapsed = Date().timeIntervalSince(lastPublicFetch)
        let interval: TimeInterval = publicIP == nil ? 15 : 60
        if !force, name == lastPublicInterface, elapsed < interval {
            return
        }
        lastPublicFetch = Date()
        lastPublicInterface = name
        if publicIP == nil, publicIPText != "Unavailable" {
            publicIPText = "…"
        }
        publicTask?.cancel()
        let generation = UUID()
        publicGeneration = generation
        let interface = pathWatch.interface(named: name)
        publicTask = Task { [weak self] in
            let ip = await PublicIPClient.fetch(interface: interface)
            guard !Task.isCancelled, let self, self.publicGeneration == generation else { return }
            self.publicIP = ip
            self.publicIPText = ip ?? "Unavailable"
        }
    }

    private func updateWiFiDemand() {
        guard selected?.kind == .wifi else { return }
        WiFiReader.shared.prepare()
    }
}

extension NetworkStatusStore {
    static var preview: NetworkStatusStore {
        let store = NetworkStatusStore(ignoresSavedPin: true)
        let subnet = SubnetCalculator.calculate(ip: "192.168.4.20", prefix: 24)
        store.interfaces = [
            LocalInterface(
                bsdName: "en2",
                displayName: "USB Ethernet",
                kind: .usbEthernet,
                ipv4: "192.168.4.20",
                prefixLength: 24,
                cidr: "192.168.4.20/24",
                mac: "00:E0:4C:10:20:30",
                gateway: "192.168.4.1",
                dnsServers: ["192.168.4.1", "1.1.1.1"],
                configuration: .dhcp,
                linkSpeedBps: 1_000_000_000,
                isPrimary: true,
                isPluggedIn: true,
                hasLink: true,
                hasGlobalIPv4: true,
                subnet: subnet,
                dhcpLeaseObtained: "22 Oct 2026, 09:14",
                dhcpLeaseExpires: "23 Oct 2026, 09:14",
                dhcpServer: "192.168.4.1"
            ),
            LocalInterface(
                bsdName: "en0",
                displayName: "Wi-Fi",
                kind: .wifi,
                ipv4: "192.168.1.42",
                prefixLength: 24,
                cidr: "192.168.1.42/24",
                mac: "—",
                gateway: "192.168.1.1",
                dnsServers: ["192.168.1.1"],
                configuration: .dhcp,
                linkSpeedBps: 0,
                isPrimary: false,
                isPluggedIn: true,
                hasLink: true,
                hasGlobalIPv4: true,
                wifiSSID: "Nightwire",
                wifiBSSID: "A8:86:DD:01:02:03",
                wifiRSSI: "72%",
                subnet: SubnetCalculator.calculate(ip: "192.168.1.42", prefix: 24)
            )
        ]
        store.neighbors = [
            NeighborDevice(ip: "192.168.4.1", mac: "F0:9F:C2:11:22:33", iface: "en2", vendor: "Ubiquiti"),
            NeighborDevice(ip: "192.168.4.50", mac: "DC:A6:32:44:55:66", iface: "en2", vendor: "Raspberry Pi"),
            NeighborDevice(ip: "192.168.1.1", mac: "B0:BE:76:10:20:30", iface: "en0", vendor: "TP-Link")
        ]
        store.resolvedName = "en2"
        store.publicIP = "203.0.113.10"
        store.publicIPText = "203.0.113.10"
        store.hasLoaded = true
        store.lastRefresh = Date(timeIntervalSince1970: 1_761_134_400)
        return store
    }
}
