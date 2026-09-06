import Charts
import SwiftUI

struct ThroughputStrip: View {
    @Bindable var store: NetworkStatusStore

    var body: some View {
        GlassPanel(cornerRadius: 14) {
            HStack(spacing: 16) {
                Text("THROUGHPUT")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(Theme.magenta)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DOWN")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textMute)
                    Text(RateFormat.bits(store.downBps))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.cyan)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("UP")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textMute)
                    Text(RateFormat.bits(store.upBps))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.hotPink)
                }

                sparkline
                    .frame(height: 36)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var sparkline: some View {
        if store.throughputHistory.isEmpty {
            Text("Sampling…")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMute)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Chart {
                ForEach(store.throughputHistory) { point in
                    LineMark(
                        x: .value("t", point.timestamp),
                        y: .value("down", point.downBps),
                        series: .value("dir", "down")
                    )
                    .foregroundStyle(Theme.cyan)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))

                    LineMark(
                        x: .value("t", point.timestamp),
                        y: .value("up", point.upBps),
                        series: .value("dir", "up")
                    )
                    .foregroundStyle(Theme.magenta)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
        }
    }
}
