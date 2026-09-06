import AppKit
import SwiftUI

struct NetworkDetailsWindow: View {
    @Bindable var store: NetworkStatusStore
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack {
            SynthwaveBackdrop()

            VStack(spacing: 0) {
                header
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                GeometryReader { geo in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            adapters
                            neighbors
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            store.detailsWindowOpen = true
        }
        .onDisappear {
            store.detailsWindowOpen = false
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            NeonText(text: "DETAILS", color: Theme.magenta, size: 18, tracking: 4)

            Text("Local adapters + neighbors")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(Theme.cyan.opacity(0.8))

            Spacer()

            if let copied = store.copiedField {
                Text(copied == "all" ? "Copied details" : "Copied \(copied)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.electric)
                    .transition(.opacity)
            }

            Button {
                store.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
            }
            .buttonStyle(.plain)
            .help("Refresh local adapters")

            Button {
                dismissWindow(id: NightwireWindowID.details)
            } label: {
                Text("HIDE")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(Theme.void)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Theme.magenta)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Close details")
        }
        .padding(.leading, 62)
        .padding(.trailing, 8)
        .animation(.easeInOut(duration: 0.18), value: store.copiedField)
    }

    @ViewBuilder
    private var adapters: some View {
        if store.snapshot.interfaces.isEmpty {
            GlassPanel(cornerRadius: 14) {
                Text("No active IPv4 interface")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMute)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        } else {
            ForEach(store.snapshot.interfaces) { iface in
                GlassPanel(cornerRadius: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(iface.title.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(1.4)
                                .foregroundStyle(Theme.hotPink)
                            if iface.isPrimary {
                                Text("PRIMARY")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.amber)
                            }
                            ConfigBadge(type: iface.configuration)
                            Spacer()
                            Button("Copy all") {
                                store.copyAll(for: iface)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.cyan)
                        }

                        detailGrid(iface)
                    }
                    .padding(12)
                }
            }
        }
    }

    private func detailGrid(_ iface: LocalInterface) -> some View {
        let rows = detailRows(iface)
        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            ForEach(rows, id: \.title) { row in
                StatusChip(title: row.title, value: row.value) {
                    store.copy(row.copyValue, field: row.title)
                }
            }
        }
    }

    private func detailRows(_ iface: LocalInterface) -> [(title: String, value: String, copyValue: String)] {
        var rows: [(String, String, String)] = [
            ("IP address", iface.ipv4, iface.ipv4),
            ("CIDR", iface.cidr, iface.cidr),
            ("MAC", iface.mac, iface.mac),
            ("Link speed", iface.linkSpeedText, iface.linkSpeedText),
            ("Gateway", iface.gateway.isEmpty ? "None" : iface.gateway, iface.gateway),
            ("DNS", iface.dnsText, iface.dnsText)
        ]
        if let subnet = iface.subnet {
            rows.append(("Network", subnet.networkAddress, subnet.networkAddress))
            rows.append(("Broadcast", subnet.broadcastAddress, subnet.broadcastAddress))
            rows.append(("Host range", subnet.hostRange, subnet.hostRange))
            rows.append(("Usable hosts", "\(subnet.usableHosts)", "\(subnet.usableHosts)"))
        }
        if let ssid = iface.wifiSSID { rows.append(("SSID", ssid, ssid)) }
        if let bssid = iface.wifiBSSID { rows.append(("BSSID", bssid, bssid)) }
        if let channel = iface.wifiChannel { rows.append(("Channel", channel, channel)) }
        if let band = iface.wifiBand { rows.append(("Band", band, band)) }
        if let phy = iface.wifiPHY { rows.append(("Radio", phy, phy)) }
        if let rssi = iface.wifiRSSI { rows.append(("Signal", rssi, rssi)) }
        if let rank = iface.serviceRank {
            rows.append(("Service order", "#\(rank)", "\(rank)"))
        }
        if let obtained = iface.dhcpLeaseObtained { rows.append(("DHCP obtained", obtained, obtained)) }
        if let expires = iface.dhcpLeaseExpires { rows.append(("DHCP expires", expires, expires)) }
        if let server = iface.dhcpServer { rows.append(("DHCP server", server, server)) }
        if store.snapshot.publicIP != nil || store.publicIPText != "…" {
            rows.append(("Public IP", store.publicIPText, store.publicIPText))
        }
        return rows
    }

    @ViewBuilder
    private var neighbors: some View {
        GlassPanel(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("NEIGHBORS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(Theme.cyan)
                    Spacer()
                    Text("\(store.snapshot.neighbors.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textMute)
                }

                if store.snapshot.neighbors.isEmpty {
                    Text("No ARP entries yet")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMute)
                } else {
                    ForEach(store.snapshot.neighbors) { neighbor in
                        HStack(spacing: 10) {
                            Text(neighbor.ip)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.text)
                            Text(neighbor.mac)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textDim)
                            Text(neighbor.vendor)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.cyan)
                            Spacer()
                            Text(neighbor.iface)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.textMute)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.copy("\(neighbor.ip) \(neighbor.mac) \(neighbor.vendor)", field: "neighbor")
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

enum DetailsWindowPresenter {
    static func existingWindow() -> NSWindow? {
        NSApp.windows.first { window in
            let id = window.identifier?.rawValue ?? ""
            return id == NightwireWindowID.details
                || id.hasSuffix(".\(NightwireWindowID.details)")
                || window.title == "Details"
        }
    }

    static func focusExisting() -> Bool {
        guard let window = existingWindow() else { return false }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}
