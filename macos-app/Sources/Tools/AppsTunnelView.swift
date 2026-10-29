import AppKit
import SwiftUI

struct AppsTunnelView: View {
    @EnvironmentObject var model: Model
    @State private var selected: [String] = []
    @State private var catalog: [MacAppInfo] = []
    @State private var picking = false
    @State private var loading = true

    var mode: String { model.settings["per_app_mode"] as? String ?? "off" }
    var listIdle: Bool { mode == "off" }

    var body: some View {
        sub(model.t("apps")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Mix(text: model.t("appsHint"), size: 13, color: C.muted)
                        .padding(.leading, 4)
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SoftSelect(
                                title: model.t("mode"),
                                value: mode,
                                options: [
                                    ("off", model.t("appsAll")),
                                    ("include", model.t("appsOnly")),
                                    ("exclude", model.t("appsExcept"))
                                ],
                                wide: true,
                                icon: "square.stack.3d.up.fill"
                            ) { model.set("per_app_mode", $0) }
                            Mix(text: modeHint, size: 12, color: C.muted)
                        }
                        .padding(14)
                    }

                    SettingsSectionLabel(text: model.t("appsSelected"))
                    SettingsCard {
                        selectedBlock
                    }
                    .opacity(listIdle ? 0.55 : 1)

                    SheetActionButton(title: model.t("appsRunning"), icon: "play.fill") { addRunning() }
                    SheetActionButton(title: model.t("appsPreset"), quiet: true) { excludeHostIDE() }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $picking) {
            AppPickerSheet(selected: $selected, catalog: $catalog) {
                persist()
            }
            .environmentObject(model)
        }
        .onAppear { load() }
    }

    @ViewBuilder
    private var selectedBlock: some View {
        if loading && selected.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Mix(text: model.t("appsLoading"), size: 13, color: C.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        } else if selected.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Mix(text: model.t("appsNone"), size: 13, color: C.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                chooseButton
            }
            .padding(14)
        } else {
            VStack(spacing: 0) {
                ForEach(selected, id: \.self) { name in
                    if name != selected.first { SettingsDivider(inset: 54) }
                    selectedRow(name)
                }
                SettingsDivider(inset: 14)
                chooseButton
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
    }

    private var chooseButton: some View {
        SheetActionButton(title: model.t("appsChoose"), primary: true, icon: "app.badge.plus") {
            picking = true
        }
        .disabled(loading)
        .opacity(loading ? 0.55 : 1)
    }

    private func selectedRow(_ name: String) -> some View {
        let app = MacAppCatalog.match(name, in: catalog)
        let title = app?.displayName ?? name
        let subtitle = app.map { $0.processName == title ? nil : $0.processName } ?? (title == name ? nil : name)
        return HStack(spacing: 12) {
            MacAppGlyph(url: app?.url ?? MacAppCatalog.url(forProcessName: name, catalog: catalog), size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Mix(text: title, size: 14, weight: .semibold)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Mix(text: subtitle, size: 11, color: C.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Button {
                remove(name)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(C.muted)
                    .frame(width: 26, height: 26)
                    .background(C.line.opacity(0.55))
                    .clipShape(Circle())
            }
            .buttonStyle(QuietPressStyle())
            .accessibilityLabel(model.t("cancel"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    var modeHint: String {
        switch mode {
        case "include": return model.t("appsOnlyHint")
        case "exclude": return model.t("appsExceptHint")
        default: return model.t("appsAllHint")
        }
    }

    func load() {
        let stored = TunnelAppList.parse(model.settings["per_app_text"] as? String ?? "")
        selected = stored
        DispatchQueue.global(qos: .userInitiated).async {
            let list = MacAppCatalog.all()
            let names = TunnelAppList.canonicalize(stored) { MacAppCatalog.match($0, in: list)?.processName }
            DispatchQueue.main.async {
                catalog = list
                selected = names
                loading = false
                if names != stored { persist() }
            }
        }
    }

    func persist() {
        model.set("per_app_text", TunnelAppList.serialize(selected))
    }

    func remove(_ name: String) {
        selected.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        persist()
    }

    func addRunning() {
        insert(MacAppCatalog.runningProcessNames())
    }

    func excludeHostIDE() {
        insert(TunnelAppList.hostIDE)
        model.set("per_app_mode", "exclude")
    }

    func insert(_ names: [String]) {
        var next = selected
        var seen = Set(next.map { $0.lowercased() })
        for raw in names {
            let name = MacAppCatalog.match(raw, in: catalog)?.processName ?? raw
            if seen.insert(name.lowercased()).inserted {
                next.append(name)
            }
        }
        selected = next
        persist()
    }
}

struct AppPickerSheet: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: [String]
    @Binding var catalog: [MacAppInfo]
    var onChange: () -> Void
    @State private var query = ""

    private var selectedSet: Set<String> {
        Set(selected.map { $0.lowercased() })
    }

    private var filtered: [MacAppInfo] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [MacAppInfo]
        if q.isEmpty {
            let picked = catalog.filter { selectedSet.contains($0.processName.lowercased()) }
            let rest = catalog.filter { !selectedSet.contains($0.processName.lowercased()) }
            base = picked + rest
        } else {
            base = catalog.filter {
                $0.displayName.localizedCaseInsensitiveContains(q)
                    || $0.processName.localizedCaseInsensitiveContains(q)
            }
        }
        return base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Mix(text: model.t("appsChoose"), size: 20, weight: .bold)
                    .lineLimit(1)
                Spacer(minLength: 0)
                SheetActionButton(title: model.t("save"), compact: true, primary: true, icon: "checkmark") {
                    dismiss()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .background(WindowMoveHandle())

            VStack(alignment: .leading, spacing: 10) {
                V2Field(placeholder: model.t("search"), text: $query, latin: true, search: true)
                Mix(
                    text: catalog.isEmpty ? model.t("appsLoading") : model.t("appsInstalled"),
                    size: 12,
                    color: C.muted
                )
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)

            if catalog.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Mix(text: model.t("appsLoading"), size: 13, color: C.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                Mix(text: model.t("appsNone"), size: 13, color: C.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { app in
                            pickerRow(app)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(minWidth: 380, idealWidth: AppFrame.width, minHeight: 520, idealHeight: AppFrame.height - 40)
        .background(C.bg)
        .presentationBackground(C.bg)
    }

    private func pickerRow(_ app: MacAppInfo) -> some View {
        let on = selectedSet.contains(app.processName.lowercased())
        return Button {
            toggle(app)
        } label: {
            HStack(spacing: 12) {
                MacAppGlyph(url: app.url, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Mix(text: app.displayName, size: 14, weight: on ? .semibold : .regular)
                        .lineLimit(1)
                    if app.processName != app.displayName {
                        Mix(text: app.processName, size: 11, color: C.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(on ? C.cyan : C.muted.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(on ? C.cyan.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityLabel(app.displayName)
    }

    private func toggle(_ app: MacAppInfo) {
        if let index = selected.firstIndex(where: { $0.caseInsensitiveCompare(app.processName) == .orderedSame }) {
            selected.remove(at: index)
        } else {
            selected.append(app.processName)
        }
        onChange()
    }
}

