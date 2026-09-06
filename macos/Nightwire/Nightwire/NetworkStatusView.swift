import SwiftUI

struct NetworkStatusView: View {
    @Bindable var store: NetworkStatusStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        GlassPanel(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("LOCAL LINK")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(Theme.cyan)

                    if let iface = store.snapshot.primary {
                        ConfigBadge(type: iface.configuration)
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
                        toggleDetails()
                    } label: {
                        Text(store.detailsWindowOpen ? "HIDE" : "DETAILS")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(Theme.void)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Theme.magenta)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(store.detailsWindowOpen ? "Close details" : "Open details in a new window")
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .animation(.easeInOut(duration: 0.18), value: store.copiedField)
        }
    }

    private func toggleDetails() {
        if store.detailsWindowOpen {
            dismissWindow(id: NightwireWindowID.details)
            return
        }
        if DetailsWindowPresenter.focusExisting() {
            store.detailsWindowOpen = true
            return
        }
        openWindow(id: NightwireWindowID.details)
    }
}

struct ConfigBadge: View {
    let type: IpConfigurationType

    var body: some View {
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
