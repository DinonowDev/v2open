import SwiftUI

struct RouteEditorView: View {
    @EnvironmentObject var model: Model
    @State private var remark = ""
    @State private var behavior = "direct"
    @State private var matchers: [MatcherRow] = []
    @State private var inbounds = ""
    @State private var sources = ""
    @State private var sourcePort = ""
    @State private var users = ""
    @State private var balancerTag = ""
    @State private var showAdvanced = false
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
                        RouteMatcherEditor(rows: $matchers)
                        Button {
                            showAdvanced.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showAdvanced ? "chevron.down" : "chevron.forward")
                                    .font(.system(size: 11, weight: .bold))
                                Mix(text: model.t("routeAdvanced"), size: 13, weight: .medium, color: C.muted)
                            }
                        }
                        .buttonStyle(QuietPressStyle())
                        if showAdvanced {
                            V2Field(label: model.t("inboundTag"), placeholder: "socks", text: $inbounds, latin: true, icon: "arrow.down.circle", axis: .vertical)
                            V2Field(label: model.t("sourceIps"), placeholder: "10.0.0.0/24", text: $sources, latin: true, icon: "network", axis: .vertical)
                            V2Field(label: model.t("sourcePort"), placeholder: "443", text: $sourcePort, latin: true, icon: "number")
                            V2Field(label: model.t("routeUsers"), placeholder: "alice", text: $users, latin: true, icon: "person", axis: .vertical)
                            V2Field(label: model.t("balancerTag"), placeholder: "balancer", text: $balancerTag, latin: true, icon: "shuffle")
                        }
                    }
                    if !error.isEmpty {
                        Mix(text: error, size: 13, color: Color(red: 1, green: 0.36, blue: 0.45))
                    }
                    SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") { saveRule() }

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
            .onAppear(perform: loadDraft)
        }
    }

    private func loadDraft() {
        remark = model.draft["remark"] as? String ?? ""
        behavior = model.draft["behavior"] as? String ?? "direct"
        let domains = multiline(model.draft["domains"])
        let ips = multiline(model.draft["ips"])
        matchers = RouteMatcherKind.rows(
            domains: domains.components(separatedBy: "\n").filter { !$0.isEmpty },
            ips: ips.components(separatedBy: "\n").filter { !$0.isEmpty },
            port: model.draft["port"] as? String ?? "",
            network: model.draft["network"] as? String ?? "",
            protocolName: model.draft["protocol"] as? String ?? ""
        )
        if matchers.isEmpty {
            matchers = [MatcherRow(kind: .domain, value: "")]
        }
        inbounds = multiline(model.draft["inbounds"])
        sources = multiline(model.draft["sources"])
        sourcePort = model.draft["source_port"] as? String ?? ""
        users = multiline(model.draft["users"])
        balancerTag = model.draft["balancer_tag"] as? String ?? ""
    }

    private func multiline(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let list = value as? [String] { return list.joined(separator: "\n") }
        return ""
    }

    private func saveRule() {
        let flat = RouteMatcherKind.flatten(matchers.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        var route: [String: Any] = [
            "remark": remark,
            "behavior": behavior,
            "domains": flat.domains.components(separatedBy: "\n").filter { !$0.isEmpty },
            "ips": flat.ips.components(separatedBy: "\n").filter { !$0.isEmpty },
            "port": flat.port,
            "network": flat.network,
            "protocol": flat.protocolName,
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
}
