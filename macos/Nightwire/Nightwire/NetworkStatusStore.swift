import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkStatusStore {
    var snapshot = NetworkSnapshot(interfaces: [], publicIP: nil, neighbors: [])
    var publicIPText = "…"
    var copiedField: String?
    var lastRefresh: Date?
    var downBps: Double = 0
    var upBps: Double = 0
    var throughputHistory: [ThroughputPoint] = []

    private var localLoop: Task<Void, Never>?
    private var publicLoop: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "nightwire.path")
    private var lastPublicFetch = Date.distantPast
    private var copyReset: Task<Void, Never>?
    private var lastCounters: (rx: UInt64, tx: UInt64, at: Date)?
    private let notifier = ChangeNotifier()

    func start() {
        guard localLoop == nil else { return }
        notifier.start()
        refreshLocal()
        refreshPublicIP(force: true)

        localLoop = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                await self.refreshLocal()
            }
        }

        publicLoop = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                if Date().timeIntervalSince(self.lastPublicFetch) >= 600 {
                    await self.refreshPublicIP(force: false)
                }
            }
        }

        pathMonitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in
                self?.refreshLocal()
                self?.refreshPublicIP(force: true)
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    func stop() {
        localLoop?.cancel()
        publicLoop?.cancel()
        localLoop = nil
        publicLoop = nil
        pathMonitor.cancel()
    }

    func refreshNow() {
        refreshLocal()
        refreshPublicIP(force: true)
    }

    func copy(_ value: String, field: String) {
        guard !value.isEmpty, value != "—" else { return }
        ClipboardCopy.string(value)
        copiedField = field
        copyReset?.cancel()
        copyReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            if self?.copiedField == field {
                self?.copiedField = nil
            }
        }
    }

    func copyAll(for iface: LocalInterface) {
        var lines = [
            "Interface: \(iface.title)",
            "IP: \(iface.ipv4)",
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
        if let publicIP = snapshot.publicIP { lines.append("Public IP: \(publicIP)") }
        copy(lines.joined(separator: "\n"), field: "all")
    }

    private func refreshLocal() {
        lastRefresh = Date()
        let interfaces = NetworkInterfaceReader.read()
        snapshot.interfaces = interfaces
        snapshot.neighbors = NeighborReader.read()
        updateThroughput(primary: snapshot.primary)
        notifier.observe(snapshot)
    }

    private func updateThroughput(primary: LocalInterface?) {
        guard let primary else { return }
        let now = Date()
        if let last = lastCounters {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0.4 {
                let down = Double(primary.rxBytes &- last.rx) / dt
                let up = Double(primary.txBytes &- last.tx) / dt
                if down >= 0, up >= 0, down < 8_000_000_000, up < 8_000_000_000 {
                    downBps = down
                    upBps = up
                    throughputHistory.append(ThroughputPoint(downBps: down, upBps: up))
                    if throughputHistory.count > 60 {
                        throughputHistory.removeFirst(throughputHistory.count - 60)
                    }
                }
            }
        }
        lastCounters = (primary.rxBytes, primary.txBytes, now)
    }

    private func refreshPublicIP(force: Bool) {
        if !force, Date().timeIntervalSince(lastPublicFetch) < 600 {
            return
        }
        lastPublicFetch = Date()
        if snapshot.publicIP == nil {
            publicIPText = "…"
        }
        Task { [weak self] in
            let ip = await Self.fetchPublicIP()
            guard let self else { return }
            self.snapshot.publicIP = ip
            self.publicIPText = ip ?? "Unavailable"
        }
    }

    private static func fetchPublicIP() async -> String? {
        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let text, !text.isEmpty, text.count <= 45 else { return nil }
            return text
        } catch {
            return nil
        }
    }
}
