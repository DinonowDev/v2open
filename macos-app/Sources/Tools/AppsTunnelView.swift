import SwiftUI

struct AppsTunnelView: View {
    @EnvironmentObject var model: Model
    @State private var apps = ""

    var mode: String { model.settings["per_app_mode"] as? String ?? "off" }

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
                            V2Field(label: model.t("apps"), placeholder: "Safari", text: $apps, latin: true, icon: "text.alignleft", axis: .vertical)
                            SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") { saveList() }
                            SheetActionButton(title: model.t("appsRunning"), icon: "play.fill") { fillRunning() }
                            SheetActionButton(title: model.t("appsPreset"), quiet: true) { excludeHostIDE() }
                        }
                        .padding(14)
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { apps = model.settings["per_app_text"] as? String ?? "" }
    }

    var modeHint: String {
        switch mode {
        case "include": return model.t("appsOnlyHint")
        case "exclude": return model.t("appsExceptHint")
        default: return model.t("appsAllHint")
        }
    }

    func saveList() {
        model.set("per_app_text", apps)
    }

    func fillRunning() {
        let names = (model.call("processes")["data"] as? [String: Any])?["names"] as? [String] ?? []
        apps = names.prefix(40).joined(separator: "\n")
    }

    func excludeHostIDE() {
        let merged = TunnelAppList.addingHostIDE(to: apps)
        apps = merged
        model.set("per_app_mode", "exclude")
        model.set("per_app_text", merged)
    }
}

enum TunnelAppList {
    static let hostIDE = [
        "Cursor",
        "Cursor Helper",
        "Cursor Helper (Plugin)",
        "Cursor Helper (Renderer)",
        "Cursor Helper (GPU)"
    ]

    static func addingHostIDE(to text: String) -> String {
        var seen = Set<String>()
        var lines: [String] = []
        let combined = text + "\n" + hostIDE.joined(separator: "\n")
        for raw in combined.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, seen.insert(line).inserted else { continue }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
