import AppKit
import SwiftUI

struct DNSView: View {
    @EnvironmentObject var model: Model
    @State private var remote = ""
    @State private var domestic = ""
    var body: some View {
        sub(model.t("dns")) {
            VStack(alignment: .leading, spacing: 16) {
                EditorSection(title: model.t("dns")) {
                    V2Field(label: model.t("remoteDns"), placeholder: "1.1.1.1", text: $remote, latin: true, icon: "globe")
                    V2Field(label: model.t("domesticDns"), placeholder: "223.5.5.5", text: $domestic, latin: true, icon: "server.rack")
                }
                SheetActionButton(title: model.t("save"), primary: true, icon: "checkmark") {
                    model.set("remote_dns", remote)
                    model.set("domestic_dns", domestic)
                    model.showToast(model.t("saved"), tone: .success)
                }
                Spacer()
            }
            .padding(.horizontal, PageLayout.horizontal)
            .padding(.top, 8)
            .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            .onAppear {
                remote = model.settings["remote_dns"] as? String ?? ""
                domestic = model.settings["domestic_dns"] as? String ?? ""
            }
        }
    }
}
