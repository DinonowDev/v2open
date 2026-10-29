import AppKit
import SwiftUI

struct RoutingView: View {
    @EnvironmentObject var model: Model
    @State private var editing = false
    @State private var showPresets = false
    @State private var fragmentPackets = ""
    @State private var fragmentLength = ""
    @State private var fragmentInterval = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            routingHeader
            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        geoRow
                        VStack(alignment: .leading, spacing: 8) {
                            SettingsSectionLabel(text: model.t("routes"))
                            SettingsCard {
                                SettingsToggleRow(title: model.t("enable"), isOn: model.settings["routing_enabled"] as? Bool ?? true) {
                                    model.set("routing_enabled", $0)
                                }
                                SettingsDivider()
                                infoSelect(model.t("strategy"), model.t("strategyInfo"), model.settings["domain_strategy"] as? String ?? "AsIs", [("AsIs", "AsIs"), ("IPIfNonMatch", "IPIfNonMatch"), ("IPOnDemand", "IPOnDemand")]) {
                                    model.set("domain_strategy", $0)
                                }
                                divider
                                infoToggle(model.t("routeOnly"), model.t("routeOnlyInfo"), model.settings["route_only"] as? Bool ?? true) { model.set("route_only", $0) }
                                divider
                                infoToggle(model.t("apple"), model.t("appleInfo"), model.settings["apple_direct"] as? Bool ?? false) { model.set("apple_direct", $0) }
                                divider
                                infoToggle(model.t("sniffing"), model.t("sniffingInfo"), model.settings["sniffing"] as? Bool ?? true) { model.set("sniffing", $0) }
                                divider
                                infoToggle(model.t("blockUdp443"), model.t("blockUdp443Info"), model.settings["block_udp_443"] as? Bool ?? true) { model.set("block_udp_443", $0) }
                                divider
                                infoToggle(model.t("bypassLan"), model.t("bypassLanInfo"), model.settings["bypass_lan"] as? Bool ?? true) { model.set("bypass_lan", $0) }
                            }
                            SettingsCard {
                                infoToggle(model.t("fragment"), model.t("fragmentInfo"), model.settings["fragment_enabled"] as? Bool ?? false) { model.set("fragment_enabled", $0) }
                                if model.settings["fragment_enabled"] as? Bool == true {
                                    divider
                                    fragmentFields
                                }
                            }
                        }
                        HStack {
                            Mix(text: model.t("moveRoutes"), size: 13, color: C.muted)
                            Spacer()
                            SettingsChipButton(title: model.t("edit"), filled: editing) { editing.toggle() }
                        }

                        SettingsCard {
                            SettingsNavRow(icon: "plus", title: model.t("addRule"), chevron: false, action: addRule)
                            ForEach(routeIds, id: \.self) { id in
                                divider
                                routeRow(id)
                            }
                        }
                    }
                    .padding(.horizontal, PageLayout.horizontal)
                    .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
                }
                .scrollIndicators(.hidden)
                if showPresets { presetOverlay }
            }
        }
        .onAppear { loadFragment() }
    }

    var fragmentFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            V2Field(label: model.t("fragmentPackets"), placeholder: "tlshello", text: $fragmentPackets, latin: true, icon: "square.split.2x1")
            V2Field(label: model.t("fragmentLength"), placeholder: "100-200", text: $fragmentLength, latin: true, icon: "ruler")
            V2Field(label: model.t("fragmentInterval"), placeholder: "10-20", text: $fragmentInterval, latin: true, icon: "timer")
            SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") { saveFragment() }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    func loadFragment() {
        fragmentPackets = model.settings["fragment_packets"] as? String ?? "tlshello"
        fragmentLength = model.settings["fragment_length"] as? String ?? "100-200"
        fragmentInterval = model.settings["fragment_interval"] as? String ?? "10-20"
    }

    func saveFragment() {
        model.set("fragment_packets", fragmentPackets)
        model.set("fragment_length", fragmentLength)
        model.set("fragment_interval", fragmentInterval)
        model.showToast(model.t("saved"), tone: .success)
    }

    var routeIds: [String] {
        model.routes.compactMap { $0["id"] as? String }.filter { !$0.isEmpty }
    }

    var routingHeader: some View {
        HStack(spacing: 12) {
            Button { model.pop() } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(C.cyan)
                    .frame(width: 32, height: 32)
                    .background(C.cyan.opacity(0.14))
                    .clipShape(Circle())
            }
            .buttonStyle(QuietPressStyle())
            .accessibilityLabel(model.t("back"))
            Mix(text: model.t("routing"), size: PageLayout.titleSize, weight: .bold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            ConfigRowMoreMenu {
                Button(model.t("importPreset")) { showPresets = true }
                Button(model.t("importRoutes")) { importClipboard() }
                Button(model.t("exportRoutes")) { exportClipboard() }
            }
        }
        .padding(.horizontal, PageLayout.horizontal)
        .padding(.top, PageLayout.top)
        .padding(.bottom, 8)
        .background(WindowMoveHandle())
    }

    var geoRow: some View {
        SettingsCard {
            SettingsNavRow(icon: "globe.americas.fill", title: model.t("geoAssets"), action: { model.push("geo_assets") })
        }
    }

    func routeRow(_ id: String) -> some View {
        let rule = model.routes.first { ($0["id"] as? String) == id } ?? [:]
        let enabled = rule["enabled"] as? Bool ?? true
        let remark = rule["remark"] as? String ?? ""
        let behavior = rule["behavior"] as? String ?? "proxy"
        let match = (rule["match"] as? String) ?? ""
        let tint: Color = {
            switch behavior {
            case "direct": return C.green
            case "block": return Color(red: 1, green: 0.36, blue: 0.45)
            default: return C.cyan
            }
        }()
        let glyph: String = {
            switch behavior {
            case "direct": return "arrow.right"
            case "block": return "xmark.shield.fill"
            default: return "arrow.triangle.swap"
            }
        }()
        return HStack(spacing: 10) {
            Button { openRule(id) } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tint.opacity(0.16))
                        Image(systemName: glyph)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Mix(text: remark.isEmpty ? model.t("addRule") : remark, size: 15, weight: .semibold)
                            .lineLimit(1)
                        Mix(
                            text: match.isEmpty ? behaviorLabel(behavior) : "\(behaviorLabel(behavior)) · \(match)",
                            size: 12,
                            color: C.muted
                        )
                        .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(QuietPressStyle())
            SoftSwitch(isOn: Binding(
                get: { enabled },
                set: { _ = model.call("toggle_route", ["id": id, "enabled": $0]); model.refresh() }
            ))
            if editing {
                VStack(spacing: 2) {
                    Button { move(id, -1) } label: {
                        Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold)).foregroundStyle(C.muted)
                    }.buttonStyle(QuietPressStyle())
                    Button { move(id, 1) } label: {
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(C.muted)
                    }.buttonStyle(QuietPressStyle())
                }
            } else {
                Button { openRule(id) } label: {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(C.muted.opacity(0.7))
                }
                .buttonStyle(QuietPressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    var presetOverlay: some View {
        SheetBackdrop(onDismiss: { showPresets = false }) {
            SheetCard {
                VStack(alignment: .leading, spacing: 8) {
                    SheetHeader(title: model.t("importPreset"), close: { showPresets = false }, closeLabel: model.t("cancel"))
                    ForEach(["global", "white", "black", "iran", "russia"], id: \.self) { name in
                        SheetActionButton(title: presetTitle(name), icon: "square.stack.3d.up") {
                            _ = model.call("preset", ["name": name])
                            model.refresh()
                            showPresets = false
                            model.showToast(model.t("imported"), tone: .success)
                        }
                    }
                    SheetActionButton(title: model.t("cancel"), quiet: true) { showPresets = false }
                }
            }
        }
    }

    func addRule() {
        model.draft = [
            "enabled": true,
            "remark": "",
            "behavior": "direct",
            "domains": "",
            "ips": "",
            "port": "",
            "network": "",
            "protocol": ""
        ]
        model.push("route_editor")
    }

    func openRule(_ id: String) {
        guard let rule = model.routes.first(where: { ($0["id"] as? String) == id }) else { return }
        var draft = rule
        draft["domains"] = ((rule["domains"] as? [String]) ?? []).joined(separator: "\n")
        draft["ips"] = ((rule["ips"] as? [String]) ?? []).joined(separator: "\n")
        model.draft = draft
        model.push("route_editor")
    }

    func importClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.showToast(model.t("clipboardEmpty"), tone: .warning)
            return
        }
        let response = model.call("import_routes", ["text": text])
        if response["ok"] as? Bool == false {
            model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
        } else {
            model.refresh()
            model.showToast(model.t("imported"), tone: .success)
        }
    }

    func exportClipboard() {
        let text = (model.call("export_routes")["data"] as? [String: Any])?["text"] as? String ?? "[]"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        model.showToast(model.t("routesCopied"), tone: .success)
    }

    func move(_ id: String, _ delta: Int) {
        var ids = routeIds
        guard let index = ids.firstIndex(of: id) else { return }
        let next = index + delta
        guard ids.indices.contains(next) else { return }
        ids.swapAt(index, next)
        _ = model.call("reorder_routes", ["ids": ids])
        model.refresh()
    }

    func presetTitle(_ name: String) -> String {
        switch name {
        case "white": return model.t("presetWhite")
        case "black": return model.t("presetBlack")
        case "iran": return model.t("presetIran")
        case "russia": return model.t("presetRussia")
        default: return model.t("presetGlobal")
        }
    }

    func behaviorLabel(_ value: String) -> String {
        switch value {
        case "direct": return model.t("behaviorDirect")
        case "block": return model.t("behaviorBlock")
        default: return model.t("behaviorProxy")
        }
    }

    var divider: some View { SettingsDivider() }
    func infoToggle(_ title: String, _ info: String, _ on: Bool, action: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 8) {
            Mix(text: title, size: 15, weight: .medium)
            InfoTip(text: info)
            Spacer()
            SoftSwitch(isOn: Binding(get: { on }, set: action))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    func infoSelect(_ title: String, _ info: String, _ value: String, _ options: [(String, String)], onSelect: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Mix(text: title, size: 12, weight: .semibold, color: C.muted)
                InfoTip(text: info)
                Spacer()
            }
            SoftSelect(value: value, options: options, wide: true, onSelect: onSelect)
        }
        .padding(14)
    }
}
