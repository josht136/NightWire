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
}

struct SynthwaveBackdrop: View {
    var body: some View {
        ZStack {
            Theme.void

            RadialGradient(
                colors: [Theme.magenta.opacity(0.28), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 520
            )
            RadialGradient(
                colors: [Theme.cyan.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 480
            )

            GridLines()
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

private struct GridLines: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 28
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(Theme.cyan.opacity(0.06)), lineWidth: 1)
                y += step
            }
        }
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
                            .fill(Theme.ink.opacity(0.55))
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

struct ConfigBadge: View {
    let type: IpConfigurationType

    var body: some View {
        Text(type.rawValue)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(1.0)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(color.opacity(0.14))
                    .overlay {
                        Capsule()
                            .strokeBorder(color.opacity(0.45), lineWidth: 1)
                    }
            }
    }

    private var color: Color {
        switch type {
        case .staticConfig:
            return Theme.magenta
        case .dhcp:
            return Theme.cyan
        case .unknown:
            return Theme.textMute
        }
    }
}

struct StatusChip: View {
    let title: String
    let value: String
    var copyable: Bool
    var onCopy: () -> Void

    var body: some View {
        Button(action: onCopy) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(Theme.textMute)
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(copyable ? Theme.text : Theme.textDim)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            }
        }
        .buttonStyle(ChipButtonStyle())
        .accessibilityLabel("\(title) \(value)")
        .accessibilityHint(copyable ? "Copies \(title)" : "")
    }
}

struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

struct KindBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(color)
    }
}
