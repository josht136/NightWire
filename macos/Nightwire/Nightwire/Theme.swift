import AppKit
import SwiftUI

enum Theme {
    static let magenta = Color(red: 1.0, green: 0.18, blue: 0.78)
    static let hotPink = Color(red: 1.0, green: 0.44, blue: 0.81)
    static let cyan = Color(red: 0.0, green: 0.96, blue: 1.0)
    static let electric = Color(red: 0.45, green: 0.95, blue: 0.72)
    static let amber = Color(red: 1.0, green: 0.82, blue: 0.28)
    static let void = Color(red: 0.03, green: 0.01, blue: 0.07)
    static let ink = Color(red: 0.07, green: 0.03, blue: 0.14)
    static let text = Color.white.opacity(0.94)
    static let textDim = Color.white.opacity(0.55)
    static let textMute = Color.white.opacity(0.34)

    static let hostColorHexes = [
        "#00F5FF",
        "#FF2EC7",
        "#FF70CF",
        "#73F2B8",
        "#FFD147",
        "#9B5CFF",
        "#FF5959",
        "#33BFFF",
        "#FF8C26",
        "#B3FF59",
        "#FF4DDB",
        "#3DFFC8"
    ]

    static let hostColors: [Color] = hostColorHexes.compactMap(Color.init(hex:))

    static func hostColor(at index: Int) -> Color {
        hostColors[abs(index) % hostColors.count]
    }

    static func hostColorHex(at index: Int) -> String {
        hostColorHexes[abs(index) % hostColorHexes.count]
    }
}

extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    func hexString() -> String {
        let converted = NSColor(self).usingColorSpace(.sRGB)
        guard let rgb = converted else { return "#FFFFFF" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

enum ClipboardCopy {
    static func string(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

struct SynthwaveBackdrop: View {
    var body: some View {
        ZStack {
            VisualEffectBackdrop(material: .underWindowBackground)
            Theme.void.opacity(0.72)

            RadialGradient(
                colors: [Theme.magenta.opacity(0.22), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 520
            )
            RadialGradient(
                colors: [Theme.cyan.opacity(0.16), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 480
            )

            GeometryReader { geo in
                Path { path in
                    let step: CGFloat = 28
                    var y: CGFloat = 0
                    while y < geo.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        y += step
                    }
                }
                .stroke(Theme.cyan.opacity(0.035), lineWidth: 1)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

struct VisualEffectBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Theme.ink.opacity(0.38))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Theme.magenta.opacity(0.55),
                                        Color.white.opacity(0.12),
                                        Theme.cyan.opacity(0.5)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: Theme.magenta.opacity(0.16), radius: 18, x: -4, y: 8)
                    .shadow(color: Theme.cyan.opacity(0.10), radius: 16, x: 6, y: -4)
            }
    }
}

struct NeonText: View {
    let text: String
    var color: Color = Theme.magenta
    var size: CGFloat = 22
    var tracking: CGFloat = 4

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .tracking(tracking)
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.85), radius: 10)
            .shadow(color: color.opacity(0.4), radius: 22)
    }
}
