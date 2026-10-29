import SwiftUI
import UniformTypeIdentifiers

struct DemandRule: Identifiable, Equatable {
    var id = UUID()
    var network: String
    var ssids: [String]
    var action: String

    var line: String {
        let name = ssids.isEmpty ? "*" : ssids.joined(separator: "|")
        return "\(network),\(name),\(action)"
    }

    static func parse(_ line: String) -> DemandRule? {
        let parts = line.split(separator: ",", maxSplits: 2).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3 else { return nil }
        let ssids = parts[1].split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "*" }
        return DemandRule(network: parts[0].isEmpty ? "any" : parts[0], ssids: ssids, action: parts[2].isEmpty ? "connect" : parts[2])
    }
}

struct OnDemandView: View {
    @EnvironmentObject var model: Model
    @State private var rules: [DemandRule] = []
    @State private var editing: DemandRule?
    @State private var isNew = false
    @State private var dragged: UUID?

    var body: some View {
        sub(model.t("onDemandTitle")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Mix(text: model.t("onDemandDesc"), size: 12, color: C.muted)
                    SettingsCard {
                        SettingsToggleRow(title: model.t("demand"), isOn: model.settings["on_demand"] as? Bool ?? false) {
                            model.set("on_demand", $0)
                        }
                    }
                    SettingsSectionLabel(text: model.t("onDemandRules"))
                    SettingsCard {
                        if rules.isEmpty {
                            Mix(text: model.t("onDemandEmpty"), size: 13, color: C.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                                    if index > 0 { SettingsDivider() }
                                    ruleRow(rule)
                                        .onDrag { dragProvider(for: rule) }
                                        .onDrop(of: [UTType.text], delegate: DemandReorderDrop(
                                            target: rule.id,
                                            rules: $rules,
                                            dragged: $dragged,
                                            persist: persist
                                        ))
                                }
                            }
                            Mix(text: model.t("onDemandReorder"), size: 11, color: C.muted)
                                .padding(.horizontal, 14)
                                .padding(.top, 4)
                                .padding(.bottom, 8)
                        }
                        SheetActionButton(title: model.t("addRule"), icon: "plus") {
                            isNew = true
                            editing = DemandRule(network: "wifi", ssids: [], action: "connect")
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                    }
                    SettingsSectionLabel(text: model.t("onDemandHow"))
                    SettingsCard {
                        Mix(text: model.t("onDemandExplainer"), size: 12, color: C.muted)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                        Mix(text: model.t("onDemandConnectHelp"), size: 12, color: C.muted)
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                        Mix(text: model.t("onDemandDisconnectHelp"), size: 12, color: C.muted)
                            .padding(.horizontal, 14)
                            .padding(.top, 4)
                        Mix(text: model.t("onDemandIgnoreHelp"), size: 12, color: C.muted)
                            .padding(.horizontal, 14)
                            .padding(.top, 4)
                            .padding(.bottom, 12)
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear { load() }
            .overlay {
                if let draft = editing {
                    DemandRuleSheet(
                        rule: draft,
                        isNew: isNew,
                        onSave: { next in
                            if isNew {
                                rules.append(next)
                            } else if let idx = rules.firstIndex(where: { $0.id == next.id }) {
                                rules[idx] = next
                            }
                            persist()
                            editing = nil
                        },
                        onClose: { editing = nil }
                    )
                }
            }
        }
    }

    func ruleRow(_ rule: DemandRule) -> some View {
        Button {
            isNew = false
            editing = rule
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Mix(text: actionLabel(rule.action), size: 14, weight: .semibold)
                    Mix(text: detail(rule), size: 11, color: C.muted)
                }
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(C.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(model.t("edit")) {
                isNew = false
                editing = rule
            }
            Button(model.t("delete"), role: .destructive) {
                rules.removeAll { $0.id == rule.id }
                persist()
            }
        }
    }

    func actionLabel(_ action: String) -> String {
        switch action {
        case "disconnect": return model.t("disconnect")
        case "ignore": return model.t("demandIgnore")
        default: return model.t("connect")
        }
    }

    func networkLabel(_ network: String) -> String {
        switch network {
        case "wifi": return model.t("demandNetworkWifi")
        case "ethernet": return model.t("demandNetworkEthernet")
        case "cellular": return model.t("demandNetworkCellular")
        default: return model.t("demandNetworkAny")
        }
    }

    func detail(_ rule: DemandRule) -> String {
        let net = networkLabel(rule.network)
        if rule.ssids.isEmpty { return net }
        return "\(net) · \(rule.ssids.joined(separator: ", "))"
    }

    func dragProvider(for rule: DemandRule) -> NSItemProvider {
        dragged = rule.id
        return NSItemProvider(object: rule.id.uuidString as NSString)
    }

    func load() {
        let text = model.settings["on_demand_text"] as? String ?? ""
        rules = text.split(separator: "\n").compactMap { DemandRule.parse(String($0)) }
    }

    func persist() {
        model.set("on_demand_text", rules.map(\.line).joined(separator: "\n"))
    }
}

struct DemandRuleSheet: View {
    @EnvironmentObject var model: Model
    @State var rule: DemandRule
    var isNew: Bool
    var onSave: (DemandRule) -> Void
    var onClose: () -> Void
    @State private var ssidDraft = ""

    var body: some View {
        SheetBackdrop(onDismiss: onClose) {
            SheetCard {
                VStack(alignment: .leading, spacing: 0) {
                    SheetHeader(
                        title: isNew ? model.t("addRule") : model.t("editRule"),
                        subtitle: model.t("onDemandRuleSettings"),
                        close: onClose,
                        closeLabel: model.t("cancel")
                    )
                    SettingsSelectRow(
                        title: model.t("demandAction"),
                        icon: "bolt",
                        value: rule.action,
                        options: [
                            ("connect", model.t("connect")),
                            ("disconnect", model.t("disconnect")),
                            ("ignore", model.t("demandIgnore"))
                        ]
                    ) { rule.action = $0 }
                    SettingsSelectRow(
                        title: model.t("demandNetwork"),
                        icon: "wifi",
                        value: rule.network,
                        options: [
                            ("any", model.t("demandNetworkAny")),
                            ("wifi", model.t("demandNetworkWifi")),
                            ("ethernet", model.t("demandNetworkEthernet")),
                            ("cellular", model.t("demandNetworkCellular"))
                        ]
                    ) { rule.network = $0 }
                    Mix(text: model.t("demandSsid"), size: 12, weight: .semibold, color: C.muted)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                    if rule.ssids.isEmpty {
                        Mix(text: model.t("demandEmptySsids"), size: 11, color: C.muted)
                            .padding(.horizontal, 14)
                            .padding(.top, 4)
                    } else {
                        FlexChips(items: rule.ssids) { name in
                            rule.ssids.removeAll { $0 == name }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 6)
                    }
                    HStack(spacing: 8) {
                        V2Field(placeholder: model.t("demandEnterSsid"), text: $ssidDraft, latin: true, icon: "tag")
                        Button {
                            let name = ssidDraft.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty, !rule.ssids.contains(name) else { return }
                            rule.ssids.append(name)
                            ssidDraft = ""
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(C.cyan)
                                .frame(width: 34, height: 34)
                                .background(C.cyan.opacity(0.14))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") { onSave(rule) }
                    SheetActionButton(title: model.t("cancel"), quiet: true, action: onClose)
                }
            }
        }
    }
}

struct DemandReorderDrop: DropDelegate {
    let target: UUID
    @Binding var rules: [DemandRule]
    @Binding var dragged: UUID?
    var persist: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        persist()
        dragged = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target,
              let from = rules.firstIndex(where: { $0.id == dragged }),
              let to = rules.firstIndex(where: { $0.id == target }) else { return }
        if from != to {
            rules.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            persist()
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

struct FlexChips: View {
    var items: [String]
    var onRemove: (String) -> Void

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(items, id: \.self) { name in
                HStack(spacing: 6) {
                    Mix(text: name, size: 12, weight: .semibold)
                    Button { onRemove(name) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(C.muted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(C.cyan.opacity(0.12))
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let origin = bounds.origin
        for item in arrange(proposal: proposal, subviews: subviews).items {
            subviews[item.index].place(
                at: CGPoint(x: origin.x + item.frame.minX, y: origin.y + item.frame.minY),
                proposal: ProposedViewSize(item.frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, items: [(index: Int, frame: CGRect)]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var width: CGFloat = 0
        var items: [(index: Int, frame: CGRect)] = []
        for (index, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            items.append((index, CGRect(origin: CGPoint(x: x, y: y), size: size)))
            x += size.width + spacing
            rowH = max(rowH, size.height)
            width = max(width, x - spacing)
        }
        return (CGSize(width: maxWidth.isFinite ? maxWidth : width, height: y + rowH), items)
    }
}
