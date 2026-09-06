import Charts
import SwiftUI

struct ChartWorkspaceView: View {
    @Bindable var monitor: PingMonitor

    var body: some View {
        VStack(spacing: 10) {
            ChartScaleBar(monitor: monitor)
            paneArea
        }
    }

    private var panes: [ChartPaneModel] {
        monitor.chartPanes()
    }

    @ViewBuilder
    private var paneArea: some View {
        if panes.isEmpty {
            GlassPanel {
                emptyWorkspace
            }
        } else {
            GeometryReader { geo in
                let columns = paneColumns(width: geo.size.width, count: panes.count)
                let rows = Int(ceil(Double(panes.count) / Double(columns)))
                let spacing: CGFloat = 10
                let height = max(210, (geo.size.height - spacing * CGFloat(max(rows - 1, 0))) / CGFloat(rows))

                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
                        spacing: spacing
                    ) {
                        ForEach(panes) { pane in
                            LatencyChartPane(pane: pane, settings: monitor.chartSettings)
                                .frame(minHeight: height)
                        }
                    }
                    .frame(minHeight: geo.size.height)
                }
            }
        }
    }

    private func paneColumns(width: CGFloat, count: Int) -> Int {
        if count <= 1 { return 1 }
        if width < 620 { return 1 }
        return 2
    }

    private var emptyWorkspace: some View {
        VStack(spacing: 8) {
            Spacer()
            NeonText(text: "SIGNAL MUTED", color: Theme.cyan, size: 18, tracking: 3)
            Text("Targets are still being pinged. Toggle an eye to plot them.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textDim)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}

struct ChartScaleBar: View {
    @Bindable var monitor: PingMonitor

    var body: some View {
        GlassPanel(cornerRadius: 14) {
            HStack(spacing: 14) {
                Text("SCALE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(Theme.magenta)

                Picker("Y-axis", selection: yAutoBinding) {
                    Text("Auto").tag(true)
                    Text("Manual").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 148)
                .help("Y-axis latency scale")

                if !monitor.chartSettings.yAuto {
                    scaleField("Min", value: yMinBinding)
                    scaleField("Max", value: yMaxBinding)
                    Text("ms")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textMute)
                }

                Spacer()

                Text("WINDOW")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(Theme.cyan)

                Picker("Time window", selection: windowBinding) {
                    ForEach(TimeWindow.allCases) { window in
                        Text(window.title).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 196)
                .help("X-axis time window")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var yAutoBinding: Binding<Bool> {
        Binding(
            get: { monitor.chartSettings.yAuto },
            set: { value in
                monitor.updateChartSettings { $0.yAuto = value }
            }
        )
    }

    private var yMinBinding: Binding<Double> {
        Binding(
            get: { monitor.chartSettings.yMin },
            set: { value in
                monitor.updateChartSettings { $0.yMin = value }
            }
        )
    }

    private var yMaxBinding: Binding<Double> {
        Binding(
            get: { monitor.chartSettings.yMax },
            set: { value in
                monitor.updateChartSettings { $0.yMax = value }
            }
        )
    }

    private var windowBinding: Binding<TimeWindow> {
        Binding(
            get: { monitor.chartSettings.timeWindow },
            set: { value in
                monitor.updateChartSettings { $0.timeWindow = value }
            }
        )
    }

    private func scaleField(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textMute)
            TextField(title, value: value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.void.opacity(0.45))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.magenta.opacity(0.28), lineWidth: 1)
                        }
                }
        }
    }
}

struct LatencyChartPane: View {
    let pane: ChartPaneModel
    let settings: ChartSettings

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pane.isGroup ? pane.title.uppercased() : pane.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(pane.isGroup ? 2.0 : 0.4)
                            .foregroundStyle(pane.isGroup ? Theme.magenta : Theme.cyan)
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMute)
                    }
                    Spacer()
                    legend
                }

                if plottedTargets.isEmpty {
                    emptyState
                } else {
                    chart
                }
            }
            .padding(12)
        }
    }

    private var subtitle: String {
        let count = pane.targets.count
        let series = count == 1 ? "1 series" : "\(count) series"
        if pane.isGroup {
            return "group overlay · \(series)"
        }
        return pane.targets.first?.address ?? series
    }

    private var windowedSamples: [(TrackedTarget, [PingSample])] {
        pane.targets.map { target in
            (target, samplesInWindow(target.samples))
        }
    }

    private var plottedTargets: [TrackedTarget] {
        windowedSamples.compactMap { pair in
            pair.1.contains(where: { $0.latencyMs != nil }) ? pair.0 : nil
        }
    }

    private func samplesInWindow(_ samples: [PingSample]) -> [PingSample] {
        guard let duration = settings.timeWindow.duration else { return samples }
        let cutoff = Date().addingTimeInterval(-duration)
        return samples.filter { $0.timestamp >= cutoff }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(pane.targets) { target in
                HStack(spacing: 5) {
                    Capsule()
                        .fill(target.color)
                        .frame(width: 12, height: 3)
                        .shadow(color: target.color.opacity(0.8), radius: 4)
                    Text(target.displayName)
                        .font(.system(size: 10, weight: .medium, design: target.hasCustomLabel ? .rounded : .monospaced))
                        .foregroundStyle(Theme.textDim)
                        .help(target.hasCustomLabel ? target.address : "")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Text(pane.targets.isEmpty ? "NO SERIES" : "WAITING FOR ECHO")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(Theme.cyan.opacity(0.8))
            Text(
                pane.targets.isEmpty
                    ? "Nothing visible in this pane."
                    : "First replies should land in a couple of seconds."
            )
            .font(.system(size: 11))
            .foregroundStyle(Theme.textDim)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chart: some View {
        Chart {
            ForEach(windowedSamples, id: \.0.id) { target, samples in
                ForEach(samples) { sample in
                    if let ms = sample.latencyMs {
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("ms", ms),
                            series: .value("Host", target.id.uuidString)
                        )
                        .foregroundStyle(target.color.opacity(0.28))
                        .lineStyle(StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("ms", ms),
                            series: .value("Host", target.id.uuidString)
                        )
                        .foregroundStyle(target.color)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("ms", ms),
                            series: .value("Host", target.id.uuidString)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [target.color.opacity(0.20), target.color.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("ms", ms)
                        )
                        .foregroundStyle(target.color)
                        .symbolSize(16)
                    }
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: xDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 5]))
                    .foregroundStyle(Theme.cyan.opacity(0.14))
                AxisValueLabel()
                    .foregroundStyle(Theme.textMute)
                    .font(.system(size: 10, design: .rounded))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 5]))
                    .foregroundStyle(Theme.magenta.opacity(0.12))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number)) ms")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Theme.textMute)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(Theme.void.opacity(0.28))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var yDomain: ClosedRange<Double> {
        if !settings.yAuto {
            return settings.clampedYDomain
        }
        let values = windowedSamples.flatMap { $0.1.compactMap(\.latencyMs) }
        let peak = values.max() ?? 50
        let floor = values.min() ?? 0
        let lower = settings.yMin > 0 ? max(0, min(settings.yMin, floor)) : 0
        let upper = max(40, ceil(peak * 1.25 / 10) * 10)
        return lower...max(lower + 1, upper)
    }

    private var xDomain: ClosedRange<Date> {
        if let duration = settings.timeWindow.duration {
            let end = Date()
            return end.addingTimeInterval(-duration)...end
        }
        let stamps = windowedSamples.flatMap { $0.1.map(\.timestamp) }
        let start = stamps.min() ?? Date().addingTimeInterval(-60)
        let end = max(stamps.max() ?? Date(), start.addingTimeInterval(1))
        return start...end
    }
}
