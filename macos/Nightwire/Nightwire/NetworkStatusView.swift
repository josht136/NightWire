import SwiftUI

struct NetworkStatusView: View {
    @Bindable var store: NetworkStatusStore
    @State private var showDetails = false

    var body: some View {
        GlassPanel(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("LOCAL LINK")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(Theme.cyan)

                    if let iface = store.snapshot.primary {
                        configBadge(iface.configuration)
                        if iface.isPrimary {
                            Text("PRIMARY")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(1.2)
                                .foregroundStyle(Theme.amber)
                        }
                    }

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
                        showDetails.toggle()
                    } label: {
                        Text(showDetails ? "HIDE" : "DETAILS")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(Theme.void)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Theme.magenta)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if let iface = store.snapshot.primary {
                    HStack(spacing: 16) {
                        StatusChip(title: "Adapter", value: iface.title) {
                            store.copy(iface.title, field: "adapter")
                        }
                        StatusChip(title: "IPv4", value: iface.cidr) {
                            store.copy(iface.ipv4, field: "IPv4")
                        }
                        StatusChip(title: "Gateway", value: iface.gateway.isEmpty ? "None" : iface.gateway) {
                            store.copy(iface.gateway, field: "gateway")
                        }
                        StatusChip(title: "DNS", value: iface.dnsText) {
                            store.copy(iface.dnsText, field: "DNS")
                        }
                        StatusChip(title: "Public IP", value: store.publicIPText) {
                            store.copy(store.publicIPText, field: "public IP")
                        }
                    }
                } else {
                    Text("No active IPv4 interface")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMute)
                        .padding(.vertical, 4)
                }

                if showDetails {
                    details
                    neighbors
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .animation(.easeInOut(duration: 0.18), value: store.copiedField)
        }
    }

    @ViewBuilder
    private var details: some View {
        Divider().overlay(Theme.magenta.opacity(0.25))

        ForEach(store.snapshot.interfaces) { iface in
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
                    configBadge(iface.configuration)
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
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.void.opacity(0.28))
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
        return rows
    }

    @ViewBuilder
    private var neighbors: some View {
        Divider().overlay(Theme.cyan.opacity(0.2))
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
            ForEach(store.snapshot.neighbors.prefix(12)) { neighbor in
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
                .onTapGesture {
                    store.copy("\(neighbor.ip) \(neighbor.mac) \(neighbor.vendor)", field: "neighbor")
                }
            }
        }
    }

    private func configBadge(_ type: IpConfigurationType) -> some View {
        Text(type.rawValue)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(1.0)
            .foregroundStyle(type == .staticConfig ? Theme.magenta : Theme.cyan)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill((type == .staticConfig ? Theme.magenta : Theme.cyan).opacity(0.14))
                    .overlay {
                        Capsule()
                            .strokeBorder((type == .staticConfig ? Theme.magenta : Theme.cyan).opacity(0.45), lineWidth: 1)
                    }
            }
    }
}

struct StatusChip: View {
    let title: String
    let value: String
    var onCopy: () -> Void

    var body: some View {
        Button(action: onCopy) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(Theme.textMute)
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("Copy \(title)")
    }
}
