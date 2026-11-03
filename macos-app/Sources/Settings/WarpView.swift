import SwiftUI

struct WarpView: View {
    @EnvironmentObject var model: Model
    @State private var name = ""
    @State private var license = ""
    @State private var wow = false
    @State private var busy = false

    private var warpProfiles: [[String: Any]] {
        model.groups.flatMap { $0["profiles"] as? [[String: Any]] ?? [] }.filter { ($0["protocol"] as? String) == "warp" }
    }

    private var chainId: String { model.settings["warp_chain_id"] as? String ?? "" }

    var body: some View {
        sub(model.t("warpTitle")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Mix(text: model.t("warpHint"), size: 13, color: C.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    SettingsSectionLabel(text: model.t("warpCreate"))
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            V2Field(label: model.fa ? "نام" : "Name", placeholder: wow ? "WARP-on-WARP" : "WARP", text: $name, latin: false, icon: "textformat")
                            V2Field(label: model.t("warpLicense"), placeholder: "xxxxxxxx-xxxxxxxx-xxxxxxxx", text: $license, latin: true, icon: "key.fill")
                        }
                        .padding(14)
                        SettingsDivider()
                        SettingsToggleRow(title: model.t("warpWow"), hint: model.t("warpWowInfo"), isOn: wow) { wow = $0 }
                    }
                    SheetActionButton(title: busy ? "…" : model.t("warpCreate"), primary: true, icon: "plus") { create() }
                        .disabled(busy)

                    SettingsSectionLabel(text: model.t("warpChain"))
                    SettingsCard {
                        SettingsToggleRow(title: model.t("warpChain"), hint: model.t("warpChainInfo"), isOn: model.settings["warp_chain"] as? Bool ?? false) { on in
                            if on && warpProfiles.isEmpty {
                                model.showToast(model.t("warpChainInvalid"), tone: .warning)
                                return
                            }
                            if on && chainId.isEmpty, let first = warpProfiles.first?["id"] as? String {
                                model.set("warp_chain_id", first)
                            }
                            model.set("warp_chain", on)
                        }
                        if !warpProfiles.isEmpty {
                            SettingsDivider()
                            SettingsSelectRow(
                                title: model.t("warpChainTarget"),
                                icon: "link",
                                value: chainId,
                                options: warpProfiles.map { ($0["id"] as? String ?? "", $0["remark"] as? String ?? "WARP") }
                            ) { model.set("warp_chain_id", $0) }
                        }
                    }

                    SettingsSectionLabel(text: model.t("warpTitle"))
                    SettingsCard {
                        if warpProfiles.isEmpty {
                            Mix(text: model.t("warpNone"), size: 13, color: C.muted)
                                .frame(maxWidth: .infinity)
                                .padding(18)
                        } else {
                            ForEach(Array(warpProfiles.enumerated()), id: \.offset) { index, profile in
                                if index > 0 { SettingsDivider(inset: 58) }
                                row(profile)
                            }
                        }
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
        }
    }

    func row(_ profile: [String: Any]) -> some View {
        let data = profile["data"] as? [String: Any] ?? [:]
        let registered = !((data["private_key"] as? String ?? "").isEmpty)
        let kind = data["account_type"] as? String ?? ""
        let detail = registered ? (kind.isEmpty ? model.t("warpRegistered") : "\(model.t("warpRegistered")) · \(kind)") : model.t("warpNotRegistered")
        let wowLabel = data["warp_wow"] as? Bool == true ? " · \(model.t("warpWow"))" : ""
        return Button {
            model.draft = data
            model.draft["id"] = profile["id"] as Any
            model.push("editor")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cloud.fill")
                    .foregroundStyle(registered ? C.cyan : C.muted)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Mix(text: profile["remark"] as? String ?? "WARP", size: 15, weight: .semibold)
                    Mix(text: detail + wowLabel, size: 12, color: C.muted)
                }
                Spacer(minLength: 0)
                if chainId == (profile["id"] as? String ?? "") && model.settings["warp_chain"] as? Bool == true {
                    Image(systemName: "link")
                        .foregroundStyle(C.cyan)
                }
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(C.muted.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    func create() {
        busy = true
        let args: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "license": license.trimmingCharacters(in: .whitespacesAndNewlines),
            "wow": wow
        ]
        Task {
            let response = await Task.detached(priority: .userInitiated) { v2RPC(method: "warp_create", args: args) }.value
            busy = false
            guard response["ok"] as? Bool != false else {
                model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
                return
            }
            model.mergeState(from: response)
            name = ""
            license = ""
            model.showToast(model.t("warpCreated"), tone: .success)
        }
    }
}
