import SwiftUI

struct RouteEditorView: View {
    @EnvironmentObject var model: Model
    @State private var remark = ""
    @State private var behavior = "direct"
    @State private var domains = ""
    @State private var ips = ""
    @State private var port = ""
    @State private var network = ""
    @State private var protocolName = ""
    @State private var error = ""

    var body: some View {
        sub(model.t("addRule")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    EditorSection(title: model.t("server")) {
                        V2Field(label: model.fa ? "نام" : "Name", placeholder: "Bypass Iran IP", text: $remark, latin: false, icon: "textformat")
                        SoftSelect(
                            title: model.t("tagBehavior"),
                            value: behavior,
                            options: [("proxy", model.t("behaviorProxy")), ("direct", model.t("behaviorDirect")), ("block", model.t("behaviorBlock"))],
                            wide: true,
                            icon: "arrow.triangle.branch",
                            onSelect: { behavior = $0 }
                        )
                    }
                    EditorSection(title: model.t("routes")) {
                        V2Field(label: model.t("domains"), placeholder: "domain:ir\ngeosite:category-ir", text: $domains, latin: true, icon: "globe", axis: .vertical)
                        V2Field(label: model.t("ips"), placeholder: "geoip:ir", text: $ips, latin: true, icon: "number", axis: .vertical)
                        V2Field(label: model.t("port"), placeholder: "443", text: $port, latin: true, icon: "number")
                        SoftSelect(
                            title: model.t("network"),
                            value: network.isEmpty ? "any" : network,
                            options: [("any", "any"), ("tcp", "tcp"), ("udp", "udp")],
                            wide: true,
                            icon: "antenna.radiowaves.left.and.right",
                            onSelect: { network = $0 == "any" ? "" : $0 }
                        )
                        V2Field(label: model.t("protocol"), placeholder: "bittorrent", text: $protocolName, latin: true, icon: "point.3.connected.trianglepath.dotted")
                    }
                    if !error.isEmpty {
                        Mix(text: error, size: 13, color: Color(red: 1, green: 0.36, blue: 0.45))
                    }
                    SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") {
                        var route: [String: Any] = [
                            "remark": remark,
                            "behavior": behavior,
                            "domains": domains,
                            "ips": ips,
                            "port": port,
                            "network": network,
                            "protocol": protocolName,
                            "enabled": model.draft["enabled"] as? Bool ?? true
                        ]
                        if let id = model.draft["id"] as? String, !id.isEmpty {
                            route["id"] = id
                        }
                        let response = model.call("save_route", ["route": route])
                        if response["ok"] as? Bool == false {
                            error = response["error"] as? String ?? model.t("failed")
                        } else {
                            model.refresh()
                            model.pop()
                        }
                    }

                    if let id = model.draft["id"] as? String, !id.isEmpty {
                        SheetActionButton(title: model.t("deleteRule"), danger: true, icon: "trash") {
                            _ = model.call("delete_route", ["id": id])
                            model.refresh()
                            model.pop()
                        }
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                remark = model.draft["remark"] as? String ?? ""
                behavior = model.draft["behavior"] as? String ?? "direct"
                domains = model.draft["domains"] as? String ?? ""
                ips = model.draft["ips"] as? String ?? ""
                port = model.draft["port"] as? String ?? ""
                network = model.draft["network"] as? String ?? ""
                protocolName = model.draft["protocol"] as? String ?? ""
            }
        }
    }
}
