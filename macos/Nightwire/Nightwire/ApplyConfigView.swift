import SwiftUI

struct ApplyConfigView: View {
    let store: NetworkStatusStore
    @State private var draft = ApplyConfigDraft()
    @State private var status: String?
    @State private var isError = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NeonText(text: "APPLY CONFIG", color: Theme.magenta, size: 16, tracking: 3)
            Text("Writes DNS and IPv4 settings on this Mac. macOS may ask for an admin password.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Adapter", selection: $draft.hardwarePort) {
                Text("Choose adapter").tag("")
                ForEach(ports, id: \.port) { item in
                    Text("\(item.port)  ·  \(item.device)").tag(item.port)
                }
            }

            Picker("Method", selection: $draft.method) {
                Text("DHCP").tag(IpConfigurationType.dhcp)
                Text("Static").tag(IpConfigurationType.staticConfig)
            }
            .pickerStyle(.segmented)

            if draft.method == .staticConfig {
                field("IPv4", text: $draft.ipv4)
                field("Subnet mask", text: $draft.subnetMask)
                field("Router", text: $draft.router)
            }

            field("DNS servers", text: $draft.dnsText)
            Text("Comma-separated. Leave empty to clear custom DNS.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMute)

            if let status {
                Text(status)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isError ? Theme.hotPink : Theme.electric)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Button("Apply to this Mac") {
                    switch NetworkConfigurator.apply(draft) {
                    case .success(let message):
                        status = message
                        isError = false
                        store.refreshNow()
                    case .failure(let error):
                        status = error.message
                        isError = true
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.void)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.magenta)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.ink)
        .onAppear { seed() }
    }

    private var ports: [(port: String, device: String)] {
        NetworkConfigurator.hardwarePorts()
    }

    private func seed() {
        guard let iface = store.snapshot.primary else { return }
        draft.hardwarePort = iface.hardwarePort ?? NetworkConfigurator.port(forBSD: iface.bsdName) ?? ""
        draft.method = iface.configuration == .staticConfig ? .staticConfig : .dhcp
        draft.ipv4 = iface.ipv4
        draft.router = iface.gateway
        draft.dnsText = iface.dnsServers.joined(separator: ", ")
        if let prefix = Int(iface.cidr.split(separator: "/").last ?? "24") {
            draft.subnetMask = prefixToMask(prefix)
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.textMute)
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.void.opacity(0.55))
                }
        }
    }

    private func prefixToMask(_ prefix: Int) -> String {
        let clamped = min(32, max(0, prefix))
        let mask: UInt32 = clamped == 0 ? 0 : UInt32.max << (32 - clamped)
        return [
            (mask >> 24) & 0xFF,
            (mask >> 16) & 0xFF,
            (mask >> 8) & 0xFF,
            mask & 0xFF
        ].map(String.init).joined(separator: ".")
    }
}
