import SwiftUI

struct ContentView: View {
    @Bindable var store: NetworkStatusStore
    var live = true

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            SynthwaveBackdrop()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                if !store.hasLoaded {
                    Spacer()
                    ProgressView()
                        .tint(Theme.cyan)
                    Text("Reading interfaces")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textDim)
                        .padding(.top, 10)
                    Spacer()
                } else if store.selected == nil {
                    ScrollView {
                        emptyState
                            .padding(.horizontal, 16)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if let iface = store.selected {
                                interfaceCard(iface)
                                neighborCard(iface)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .refreshable {
                        await store.refreshNow()
                    }
                }
            }
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .preferredColorScheme(.dark)
        .task {
            guard live else { return }
            store.start()
        }
        .onChange(of: scenePhase) { _, phase in
            guard live else { return }
            if phase == .background {
                store.pausePolling()
            } else if phase == .active {
                store.resumePolling()
                Task { await store.refreshNow() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                NeonText(text: "DETAILS", size: 18, tracking: 4)
                Text("Local adapter")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Theme.cyan.opacity(0.8))
                Spacer(minLength: 8)
                if let copied = store.copiedField {
                    Text(copied == "all" ? "Copied details" : "Copied \(copied)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.electric)
                        .transition(.opacity)
                }
                Button {
                    Task { await store.refreshNow() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(ChipButtonStyle())
                .accessibilityLabel("Refresh")
            }

            interfaceMenu

            Text(store.selectionCaption)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textDim)
        }
        .animation(.easeInOut(duration: 0.18), value: store.copiedField)
    }

    private var interfaceMenu: some View {
        Menu {
            Button {
                store.pin(nil)
            } label: {
                if store.pinnedName == nil {
                    Label("Automatic", systemImage: "checkmark")
                } else {
                    Text("Automatic")
                }
            }

            if !store.interfaces.isEmpty {
                Divider()
            }

            ForEach(store.interfaces) { iface in
                Button {
                    store.pin(iface.bsdName)
                } label: {
                    if store.pinnedName == iface.bsdName {
                        Label(iface.menuTitle, systemImage: "checkmark")
                    } else {
                        Label(iface.menuTitle, systemImage: symbol(for: iface.kind))
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol(for: store.selected?.kind ?? .other))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selected?.title ?? "No interface")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if let refreshed = store.lastRefresh {
                        Text(refreshed.formatted(date: .omitted, time: .standard))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textMute)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.cyan.opacity(0.35), lineWidth: 1)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Network interface")
    }

    private var emptyState: some View {
        GlassPanel(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("No network interface is up")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("Plug in a USB Ethernet adapter, or turn on Wi-Fi or cellular.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMute)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private func interfaceCard(_ iface: LocalInterface) -> some View {
        let rows = DetailRows.make(iface: iface, publicIPText: store.publicIPText)
        return GlassPanel(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(iface.title.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(Theme.hotPink)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Copy all") {
                        store.copyAll(for: iface)
                    }
                    .buttonStyle(ChipButtonStyle())
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.cyan)
                }

                HStack(spacing: 8) {
                    if iface.kind == .usbEthernet {
                        KindBadge(text: "DONGLE", color: Theme.electric)
                    }
                    if iface.isPrimary {
                        KindBadge(text: "PRIMARY", color: Theme.amber)
                    }
                    ConfigBadge(type: iface.configuration)
                    if !iface.hasLink {
                        KindBadge(text: "NO CARRIER", color: Theme.amber)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 128), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(rows) { row in
                        StatusChip(
                            title: row.title,
                            value: row.value,
                            copyable: DetailRows.isCopyable(row.copyValue)
                        ) {
                            store.copy(row.copyValue, field: row.title)
                        }
                    }
                }

                if let note = DetailRows.wifiFootnote(for: iface) {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMute)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Tap a value to copy it.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textMute)
            }
            .padding(12)
        }
    }

    private func neighborCard(_ iface: LocalInterface) -> some View {
        let neighbors = store.visibleNeighbors
        return GlassPanel(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("NEIGHBORS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(Theme.cyan)
                    Text(iface.bsdName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textMute)
                    Spacer()
                    Text("\(neighbors.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textMute)
                }

                if store.neighborsUnavailable {
                    Text("ARP table is not available on this device.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMute)
                } else if neighbors.isEmpty {
                    Text("No ARP entries yet")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMute)
                } else {
                    ForEach(neighbors) { neighbor in
                        Button {
                            store.copy(
                                "\(neighbor.ip) \(neighbor.mac) \(neighbor.vendor)",
                                field: "neighbor"
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(neighbor.ip)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.text)
                                HStack(spacing: 8) {
                                    Text(neighbor.mac)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Theme.textDim)
                                    Text(neighbor.vendor)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(Theme.cyan)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(ChipButtonStyle())
                    }
                }
            }
            .padding(12)
        }
    }

    private func symbol(for kind: InterfaceKind) -> String {
        switch kind {
        case .usbEthernet:
            return "cable.connector"
        case .wifi:
            return "wifi"
        case .cellular:
            return "antenna.radiowaves.left.and.right"
        case .other:
            return "network"
        }
    }
}

#Preview {
    ContentView(store: .preview, live: false)
}
