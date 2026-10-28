import SwiftUI

struct GeoAssetsView: View {
    @EnvironmentObject var model: Model
    @State private var name = ""
    @State private var url = ""
    @State private var adding = false
    @State private var busy = ""

    var body: some View {
        sub(model.t("geoAssets")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsCard {
                        SettingsNavRow(icon: "plus", title: model.t("addAsset"), chevron: false) {
                            withAnimation(.easeOut(duration: 0.18)) { adding.toggle() }
                        }
                    }

                    if adding {
                        SettingsCard {
                            VStack(alignment: .leading, spacing: 12) {
                                V2Field(label: model.t("assetName"), placeholder: "iran.dat", text: $name, latin: true, icon: "doc")
                                V2Field(label: model.t("assetUrl"), placeholder: "https://", text: $url, latin: true, pasteable: true, icon: "link")
                                SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") {
                                    let response = model.call("add_geo_asset", ["name": name, "url": url])
                                    if response["ok"] as? Bool == false {
                                        model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
                                    } else {
                                        model.refresh()
                                        name = ""
                                        url = ""
                                        adding = false
                                        model.showToast(model.t("imported"), tone: .success)
                                    }
                                }
                            }
                            .padding(14)
                        }
                    }

                    SettingsCard {
                        if model.geoAssets.isEmpty {
                            Mix(text: model.t("empty"), size: 13, color: C.muted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(18)
                        } else {
                            ForEach(Array(model.geoAssets.enumerated()), id: \.offset) { index, asset in
                                if index > 0 { SettingsDivider(inset: 58) }
                                assetRow(asset)
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

    func assetRow(_ asset: [String: Any]) -> some View {
        let file = asset["name"] as? String ?? ""
        let exists = asset["exists"] as? Bool ?? false
        let size = asset["size"] as? Int ?? Int(asset["size"] as? Double ?? 0)
        let builtin = asset["builtin"] as? Bool ?? true
        let updating = busy == file
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((exists ? C.cyan : Color(red: 1, green: 0.72, blue: 0.38)).opacity(0.16))
                Image(systemName: exists ? "globe.americas.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(exists ? C.cyan : Color(red: 1, green: 0.72, blue: 0.38))
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Mix(text: file, size: 15, weight: .semibold)
                Mix(text: exists ? sizeLabel(size) : model.t("missingAsset"), size: 12, color: C.muted)
            }
            Spacer()
            if updating {
                ProgressView().controlSize(.small)
            } else {
                SettingsChipButton(title: model.t("updateAsset")) {
                    busy = file
                    DispatchQueue.global(qos: .userInitiated).async {
                        let response = v2RPC(method: "update_geo_asset", args: ["name": file])
                        DispatchQueue.main.async {
                            busy = ""
                            if response["ok"] as? Bool == false {
                                model.showToast(response["error"] as? String ?? model.t("failed"), tone: .error)
                            } else {
                                model.mergeState(from: response)
                                model.showToast(model.t("imported"), tone: .success)
                            }
                        }
                    }
                }
            }
            if !builtin {
                Button {
                    _ = model.call("delete_geo_asset", ["name": file])
                    model.refresh()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.36, blue: 0.45))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(QuietPressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    func sizeLabel(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1f MB", Double(n) / 1_000_000) }
        if n >= 1000 { return String(format: "%.0f KB", Double(n) / 1000) }
        return "\(n) B"
    }

}
