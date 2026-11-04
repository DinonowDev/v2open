import Charts
import SwiftUI

private enum ClashConnFilter: String, CaseIterable, Identifiable {
    case all, tcp, udp, direct, proxy
    var id: String { rawValue }
}

private enum ClashConnSort: String, CaseIterable, Identifiable {
    case recent, download, upload
    var id: String { rawValue }
}

private struct TrafficSample: Identifiable {
    let id = UUID()
    let time: Date
    let download: Double
    let upload: Double
}

struct ClashStatusView: View {
    @EnvironmentObject var model: Model
    @State private var data: [String: Any] = [:]
    @State private var delays: [String: Int] = [:]
    @State private var busy = ""
    @State private var search = ""
    @State private var filter: ClashConnFilter = .all
    @State private var sort: ClashConnSort = .recent
    @State private var trafficHistory: [TrafficSample] = []
    @State private var lastTotals: (up: UInt64, down: UInt64, at: Date)?
    @State private var speedByID: [String: (up: Int, down: Int)] = [:]
    @State private var lastBytesByID: [String: (up: UInt64, down: UInt64)] = [:]
    @State private var lastSpeedAt: [String: Date] = [:]

    var body: some View {
        sub(model.t("clashApi")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCard {
                        row("Port", "\(jsonInt(data["port"]))")
                        SettingsDivider()
                        row(model.t("connected"), (data["connected"] as? Bool == true) ? model.t("connected") : model.t("disconnected"))
                        SettingsDivider()
                        row(model.t("upload"), formatBytes(jsonUInt(data["upload_total"])))
                        SettingsDivider()
                        row(model.t("download"), formatBytes(jsonUInt(data["download_total"])))
                    }

                    if !trafficHistory.isEmpty {
                        SettingsSectionLabel(text: model.t("clashTrafficHistory"))
                        SettingsCard {
                            Chart(trafficHistory) { sample in
                                LineMark(
                                    x: .value("t", sample.time),
                                    y: .value("down", sample.download)
                                )
                                .foregroundStyle(C.cyan)
                                LineMark(
                                    x: .value("t", sample.time),
                                    y: .value("up", sample.upload)
                                )
                                .foregroundStyle(C.speedUp)
                            }
                            .chartYAxisLabel(model.t("unitMBps"))
                            .frame(height: 140)
                            .padding(12)
                        }
                    }

                    SettingsSectionLabel(text: model.t("clashProxies"))
                    SettingsCard {
                        let proxies = data["proxies"] as? [String: Any] ?? [:]
                        let names = proxies.keys.sorted()
                        if names.isEmpty {
                            Mix(text: model.t("empty"), size: 13, color: C.muted)
                                .padding(14)
                        } else {
                            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                                if index > 0 { SettingsDivider() }
                                proxyRow(name: name, item: proxies[name] as? [String: Any] ?? [:])
                            }
                        }
                    }

                    SettingsSectionLabel(text: model.t("clashConnections"))
                    SettingsCard {
                        V2Field(placeholder: model.t("search"), text: $search, icon: "magnifyingglass")
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ClashConnFilter.allCases) { item in
                                    filterChip(item)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        Picker("", selection: $sort) {
                            Text(model.t("clashSortRecent")).tag(ClashConnSort.recent)
                            Text(model.t("clashSortDownload")).tag(ClashConnSort.download)
                            Text(model.t("clashSortUpload")).tag(ClashConnSort.upload)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)

                        let rows = filteredConnections()
                        if rows.isEmpty {
                            Mix(text: model.t("clashNoMatch"), size: 13, color: C.muted)
                                .padding(14)
                        } else {
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, item in
                                if index > 0 { SettingsDivider() }
                                connectionRow(item)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        SheetActionButton(title: model.t("update"), primary: true, icon: "arrow.clockwise") { load() }
                        SheetActionButton(title: model.t("closeAll"), danger: true, icon: "xmark.circle") {
                            _ = model.call("clash_close", ["id": ""])
                            load()
                        }
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear { load() }
            .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
                if model.current == "clash_status" { load() }
            }
        }
    }

    func filterChip(_ item: ClashConnFilter) -> some View {
        let title: String
        switch item {
        case .all: title = model.t("clashFilterAll")
        case .tcp: title = model.t("clashFilterTcp")
        case .udp: title = model.t("clashFilterUdp")
        case .direct: title = model.t("clashFilterDirect")
        case .proxy: title = model.t("clashFilterProxy")
        }
        let active = filter == item
        return Button {
            filter = item
        } label: {
            Mix(text: title, size: 11, weight: active ? .bold : .medium, color: active ? C.onAccent : C.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(active ? C.cyan : C.overlay.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    func filteredConnections() -> [[String: Any]] {
        var rows = data["connections"] as? [[String: Any]] ?? []
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            rows = rows.filter { row in
                let blob = connectionSearchBlob(row).lowercased()
                return blob.contains(query)
            }
        }
        switch filter {
        case .all: break
        case .tcp:
            rows = rows.filter { ($0["network"] as? String ?? "").lowercased() == "tcp" }
        case .udp:
            rows = rows.filter { ($0["network"] as? String ?? "").lowercased() == "udp" }
        case .direct:
            rows = rows.filter { isDirectConnection($0) }
        case .proxy:
            rows = rows.filter { !isDirectConnection($0) }
        }
        switch sort {
        case .recent:
            rows.sort { jsonUInt($0["start"]) > jsonUInt($1["start"]) }
        case .download:
            rows.sort { jsonUInt($0["download"]) > jsonUInt($1["download"]) }
        case .upload:
            rows.sort { jsonUInt($0["upload"]) > jsonUInt($1["upload"]) }
        }
        return rows
    }

    func connectionSearchBlob(_ item: [String: Any]) -> String {
        let chains = (item["chains"] as? [String] ?? []).joined(separator: " ")
        let parts = [
            item["host"] as? String,
            item["process"] as? String,
            item["rule"] as? String,
            item["rulePayload"] as? String,
            item["network"] as? String,
            chains
        ]
        return parts.compactMap { $0 }.joined(separator: " ")
    }

    func isDirectConnection(_ item: [String: Any]) -> Bool {
        let chains = item["chains"] as? [String] ?? []
        if chains.isEmpty { return false }
        return chains.allSatisfy { $0.uppercased().contains("DIRECT") }
    }

    func proxyRow(name: String, item: [String: Any]) -> some View {
        let kind = item["type"] as? String ?? ""
        let now = item["now"] as? String ?? ""
        let all = item["all"] as? [String] ?? []
        let history = item["history"] as? [[String: Any]] ?? []
        let delay = delays[name] ?? jsonInt(history.last?["delay"])
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Mix(text: name, size: 13, weight: .semibold)
                    Mix(text: [kind, now].filter { !$0.isEmpty }.joined(separator: "  ·  "), size: 11, color: C.muted)
                }
                Spacer()
                if delay > 0 {
                    Mix(text: "\(delay) ms", size: 11, weight: .semibold, color: C.cyan)
                }
                Button {
                    busy = name
                    let response = model.call("clash_delay", ["name": name])
                    if let ms = (response["data"] as? [String: Any]).flatMap({ jsonInt($0["delay"]) }), ms > 0 {
                        delays[name] = ms
                    }
                    busy = ""
                } label: {
                    Image(systemName: busy == name ? "hourglass" : "timer")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(C.cyan)
                }
                .buttonStyle(.plain)
            }
            if !all.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(all, id: \.self) { option in
                            Button {
                                _ = model.call("clash_select", ["group": name, "name": option])
                                load()
                            } label: {
                                Mix(text: option, size: 11, weight: option == now ? .bold : .medium, color: option == now ? C.onAccent : C.text)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(option == now ? C.cyan : C.overlay.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    func connectionRow(_ item: [String: Any]) -> some View {
        let host = item["host"] as? String ?? "-"
        let network = item["network"] as? String ?? ""
        let process = item["process"] as? String ?? ""
        let rule = item["rule"] as? String ?? ""
        let payload = item["rulePayload"] as? String ?? ""
        let chains = (item["chains"] as? [String] ?? []).joined(separator: " → ")
        let id = item["id"] as? String ?? ""
        let up = jsonUInt(item["upload"])
        let down = jsonUInt(item["download"])
        let speeds = speedByID[id] ?? (0, 0)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Mix(text: host, size: 13, weight: .semibold)
                    Mix(text: [network, process].filter { !$0.isEmpty }.joined(separator: " · "), size: 11, color: C.muted)
                }
                Spacer()
                Button {
                    _ = model.call("clash_close", ["id": id])
                    load()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(C.muted)
                }
                .buttonStyle(.plain)
            }
            if !rule.isEmpty || !payload.isEmpty {
                Mix(
                    text: "\(model.t("clashRule")): \(rule)\(payload.isEmpty ? "" : " / \(payload)")",
                    size: 11,
                    color: C.muted
                )
            }
            if !chains.isEmpty {
                Mix(text: "\(model.t("clashChains")): \(chains)", size: 11, color: C.muted)
            }
            HStack(spacing: 12) {
                Mix(text: "↑ \(formatBytes(up))", size: 11, color: C.muted)
                Mix(text: "↓ \(formatBytes(down))", size: 11, color: C.muted)
                if speeds.up > 0 || speeds.down > 0 {
                    Mix(
                        text: "\(model.t("clashSpeed")): ↑\(formatBps(speeds.up)) ↓\(formatBps(speeds.down))",
                        size: 11,
                        color: C.cyan
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    func row(_ title: String, _ value: String) -> some View {
        HStack {
            Mix(text: title, size: 13, color: C.muted)
            Spacer()
            Mix(text: value.isEmpty ? "-" : value, size: 13, weight: .semibold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    func load() {
        let response = model.call("clash_status")
        data = response["data"] as? [String: Any] ?? [:]
        recordTrafficTotals()
        updateConnectionSpeeds()
    }

    func recordTrafficTotals() {
        let up = jsonUInt(data["upload_total"])
        let down = jsonUInt(data["download_total"])
        let now = Date()
        if let last = lastTotals {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0.5 {
                let upDelta = up >= last.up ? up - last.up : 0
                let downDelta = down >= last.down ? down - last.down : 0
                let upRate = Double(upDelta) / dt / 1_000_000
                let downRate = Double(downDelta) / dt / 1_000_000
                trafficHistory.append(TrafficSample(time: now, download: max(0, downRate), upload: max(0, upRate)))
                if trafficHistory.count > 40 {
                    trafficHistory.removeFirst(trafficHistory.count - 40)
                }
            }
        }
        lastTotals = (up, down, now)
    }

    func updateConnectionSpeeds() {
        let now = Date()
        let rows = data["connections"] as? [[String: Any]] ?? []
        for row in rows {
            guard let id = row["id"] as? String, !id.isEmpty else { continue }
            let up = jsonUInt(row["upload"])
            let down = jsonUInt(row["download"])
            if let previous = lastBytesByID[id], let lastAt = lastSpeedAt[id] {
                let dt = now.timeIntervalSince(lastAt)
                if dt > 0.2 {
                    let upDelta = up >= previous.up ? up - previous.up : 0
                    let downDelta = down >= previous.down ? down - previous.down : 0
                    let upBps = Int(Double(upDelta) / dt)
                    let downBps = Int(Double(downDelta) / dt)
                    speedByID[id] = (max(0, upBps), max(0, downBps))
                }
            }
            lastBytesByID[id] = (up, down)
            lastSpeedAt[id] = now
            if speedByID[id] == nil {
                speedByID[id] = (0, 0)
            }
        }
    }
}
