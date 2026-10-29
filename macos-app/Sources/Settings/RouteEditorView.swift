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
    @State private var inbounds = ""
    @State private var sources = ""
    @State private var sourcePort = ""
    @State private var users = ""
    @State private var balancerTag = ""
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
                    EditorSection(title: model.t("routeAdvanced")) {
                        V2Field(label: model.t("inboundTag"), placeholder: "socks", text: $inbounds, latin: true, icon: "arrow.down.circle", axis: .vertical)
                        V2Field(label: model.t("sourceIps"), placeholder: "10.0.0.0/24", text: $sources, latin: true, icon: "network", axis: .vertical)
                        V2Field(label: model.t("sourcePort"), placeholder: "443", text: $sourcePort, latin: true, icon: "number")
                        V2Field(label: model.t("routeUsers"), placeholder: "alice", text: $users, latin: true, icon: "person", axis: .vertical)
                        V2Field(label: model.t("balancerTag"), placeholder: "balancer", text: $balancerTag, latin: true, icon: "shuffle")
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
                            "inbounds": inbounds,
                            "sources": sources,
                            "source_port": sourcePort,
                            "users": users,
                            "balancer_tag": balancerTag,
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
                inbounds = model.draft["inbounds"] as? String ?? ""
                sources = model.draft["sources"] as? String ?? ""
                sourcePort = model.draft["source_port"] as? String ?? ""
                users = model.draft["users"] as? String ?? ""
                balancerTag = model.draft["balancer_tag"] as? String ?? ""
            }
        }
    }
}
