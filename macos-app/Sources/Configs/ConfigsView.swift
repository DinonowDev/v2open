import SwiftUI

struct ConfigsView: View {
    @EnvironmentObject var model: Model
    @State var addStep: ConfigAddStep = .none
    @State var query = ""
    @State var lockedImportB64: String?
    @State var filePassword = ""
    @State var collapsedGroups: Set<String> = []
    @State var shareProfile: [String: Any]?
    @State var shareGroupId = ""
    @State var qrProfile: [String: Any]?

    var body: some View {
        let groups = filteredGroups()
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ConfigSearchHeader(
                        query: $query,
                        title: model.t("configs"),
                        placeholder: model.t("search"),
                        latin: !model.fa
                    )

                    ConfigActionBar(
                        sortTitle: "\(model.t("sort")) · \(sortLabel())",
                        addTitle: model.t("add"),
                        qrTitle: model.t("qr"),
                        pingTitle: model.t("pingAll"),
                        onAdd: { addStep = .menu },
                        onQR: { addStep = .scan },
                        onSort: { cycleSort() },
                        onPing: { runPing(profileIds: Set(model.allProfileIds()), args: pingArgs()) }
                    )
                    .padding(.top, 10)
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.bottom, 8)
                .background(C.bgGradientTop)
                .zIndex(1)

                GeometryReader { geo in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(groups.indices, id: \.self) { index in
                                groupCard(groups[index])
                                    .frame(maxWidth: .infinity)
                            }
                            if groups.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "tray")
                                        .font(.system(size: 28, weight: .light))
                                        .foregroundStyle(C.muted.opacity(0.7))
                                    Mix(text: model.t("empty"), size: PageLayout.subtitleSize, color: C.muted)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 36)
                            }
                        }
                        .padding(.horizontal, PageLayout.horizontal)
                        .padding(.top, 6)
                        .padding(.bottom, PageLayout.tabBarClearance + (model.selectedProfile == nil ? 0 : PageLayout.dockClearance))
                        .frame(width: geo.size.width, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    .contentMargins(.trailing, 0, for: .scrollIndicators)
                    .background(HairlineScrollInstaller())
                    .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }

            if model.selectedProfile != nil {
                ConfigConnectDock()
                    .padding(.horizontal, 14)
                    .padding(.bottom, PageLayout.tabBarClearance)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if addStep == .menu { addMenuOverlay }
            if addStep == .scan { addScanOverlay }
            if lockedImportB64 != nil { filePasswordOverlay }
            if let profile = shareProfile {
                ProfileShareSheet(profile: profile, groupId: shareGroupId) { shareProfile = nil }
            }
            if let profile = qrProfile {
                ProfileQRSheet(profile: profile) { qrProfile = nil }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: addStep)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: lockedImportB64 != nil)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: model.settings["selected_id"] as? String ?? "")
    }
}
