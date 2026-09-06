import SwiftUI

struct SidebarView: View {
    @Bindable var monitor: PingMonitor

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("TARGETS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(2.4)
                        .foregroundStyle(Theme.cyan)
                    Spacer()
                    Text("\(monitor.targets.count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(sidebarSections, id: \.title) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .tracking(1.6)
                                    .foregroundStyle(section.isGroup ? Theme.magenta : Theme.textMute)
                                ForEach(section.targets) { target in
                                    TargetRow(target: target, monitor: monitor)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("IP or hostname", text: $monitor.addText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .onSubmit { monitor.addCurrent() }

                        Button {
                            monitor.addCurrent()
                        } label: {
                            Text("ADD")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .tracking(1.2)
                                .foregroundStyle(Theme.void)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.cyan)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .shadow(color: Theme.cyan.opacity(0.55), radius: 8)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.void.opacity(0.45))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.magenta.opacity(0.35), lineWidth: 1)
                            }
                    }

                    if let error = monitor.addError {
                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.hotPink)
                    } else {
                        Text("Return to add · tag a group to share a pane")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMute)
                    }
                }
            }
            .padding(14)
        }
    }

    private var sidebarSections: [(title: String, isGroup: Bool, targets: [TrackedTarget])] {
        var groups: [String: [TrackedTarget]] = [:]
        var solos: [TrackedTarget] = []
        for target in monitor.targets {
            if target.hasGroup {
                groups[target.trimmedGroup, default: []].append(target)
            } else {
                solos.append(target)
            }
        }
        let named = groups.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var sections = named.map { name in
            (title: name.uppercased(), isGroup: true, targets: groups[name] ?? [])
        }
        if !solos.isEmpty {
            sections.append((title: "OWN PANE", isGroup: false, targets: solos))
        }
        return sections
    }
}

struct TargetRow: View {
    @Bindable var target: TrackedTarget
    @Bindable var monitor: PingMonitor
    @State private var showColorPicker = false
    @State private var showGroupPicker = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                monitor.toggleVisibility(target)
            } label: {
                Image(systemName: target.isVisibleOnChart ? "eye.fill" : "eye.slash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(target.isVisibleOnChart ? target.color : Theme.textMute)
                    .shadow(color: target.isVisibleOnChart ? target.color.opacity(0.7) : .clear, radius: 8)
                    .frame(width: 22)
            }
            .buttonStyle(.plain)
            .help(target.isVisibleOnChart ? "Hide from chart" : "Show on chart")

            VStack(alignment: .leading, spacing: 2) {
                TextField(target.address, text: $target.label)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold, design: target.hasCustomLabel ? .rounded : .monospaced))
                    .foregroundStyle(Theme.text)
                    .onSubmit { monitor.setLabel(target, target.label) }
                    .onChange(of: target.label) {
                        monitor.persist(target)
                    }

                if target.hasCustomLabel {
                    Text(target.address)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if target.role == .gateway {
                        Text("GATEWAY")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(Theme.amber)
                    }
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(statusColor)
                }

                Button {
                    showGroupPicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.split.2x1")
                            .font(.system(size: 9, weight: .semibold))
                        Text(target.hasGroup ? target.trimmedGroup : "Own pane")
                            .lineLimit(1)
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(target.hasGroup ? Theme.magenta : Theme.textMute)
                }
                .buttonStyle(.plain)
                .help("Assign a group to overlay this host with others")
                .popover(isPresented: $showGroupPicker, arrowEdge: .trailing) {
                    GroupPicker(
                        current: target.trimmedGroup,
                        existing: monitor.knownGroups
                    ) { name in
                        monitor.setGroup(target, name)
                        showGroupPicker = false
                    }
                }
            }

            Spacer(minLength: 4)

            Button {
                showColorPicker.toggle()
            } label: {
                Circle()
                    .fill(target.color)
                    .frame(width: 12, height: 12)
                    .shadow(color: target.color.opacity(0.8), radius: 6)
                    .opacity(target.isVisibleOnChart ? 1 : 0.25)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help("Chart color")
            .popover(isPresented: $showColorPicker, arrowEdge: .trailing) {
                SeriesColorPicker(currentHex: target.colorHex ?? Theme.hostColorHex(at: target.colorIndex)) { hex, index in
                    monitor.setColor(target, hex: hex, paletteIndex: index)
                }
            }

            Button {
                monitor.remove(target)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 18, height: 18)
                    .background(Theme.void.opacity(0.4))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Stop tracking")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.void.opacity(target.isVisibleOnChart ? 0.28 : 0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(target.color.opacity(target.isVisibleOnChart ? 0.45 : 0.14), lineWidth: 1)
                }
        }
    }

    private var statusText: String {
        target.lastResult?.display ?? "waiting…"
    }

    private var statusColor: Color {
        switch target.lastResult {
        case .success:
            return Theme.electric
        case .timeout, .unresolved, .failed:
            return Theme.hotPink
        case nil:
            return Theme.textMute
        }
    }
}

struct SeriesColorPicker: View {
    let currentHex: String
    var onPick: (String, Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SERIES COLOR")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(Theme.cyan)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 6), spacing: 8) {
                ForEach(Array(Theme.hostColorHexes.enumerated()), id: \.offset) { index, hex in
                    Button {
                        onPick(hex, index)
                    } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? Theme.cyan)
                            .frame(width: 22, height: 22)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        currentHex.caseInsensitiveCompare(hex) == .orderedSame
                                            ? Color.white
                                            : Color.white.opacity(0.2),
                                        lineWidth: currentHex.caseInsensitiveCompare(hex) == .orderedSame ? 2 : 1
                                    )
                            }
                            .shadow(color: (Color(hex: hex) ?? Theme.cyan).opacity(0.55), radius: 5)
                    }
                    .buttonStyle(.plain)
                }
            }

            ColorPicker(
                "Custom",
                selection: Binding(
                    get: { Color(hex: currentHex) ?? Theme.cyan },
                    set: { onPick($0.hexString(), nil) }
                ),
                supportsOpacity: false
            )
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textDim)
        }
        .padding(14)
        .frame(width: 228)
        .background(Theme.ink.opacity(0.4))
    }
}

struct GroupPicker: View {
    let current: String
    let existing: [String]
    var onPick: (String) -> Void
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHART GROUP")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(Theme.cyan)

            Text("Same group shares one pane. Empty keeps its own pane.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMute)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onPick("")
            } label: {
                rowLabel("Own pane", selected: current.isEmpty)
            }
            .buttonStyle(.plain)

            ForEach(existing, id: \.self) { name in
                Button {
                    onPick(name)
                } label: {
                    rowLabel(name, selected: current.caseInsensitiveCompare(name) == .orderedSame)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                TextField("New group", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .onSubmit { submitDraft() }
                Button("Set") { submitDraft() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.cyan)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.void.opacity(0.5))
            }
        }
        .padding(14)
        .frame(width: 220)
        .background(Theme.ink.opacity(0.4))
        .onAppear { draft = current }
    }

    private func submitDraft() {
        onPick(draft)
    }

    private func rowLabel(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: selected ? .bold : .medium, design: .rounded))
                .foregroundStyle(selected ? Theme.cyan : Theme.text)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.cyan)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Theme.cyan.opacity(0.12) : Color.clear)
        }
    }
}
