import SwiftUI

struct BackupSettingsView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        sub(model.t("backup")) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCard {
                        SettingsNavRow(icon: "square.and.arrow.up", title: model.t("backupNow"), chevron: false) {
                            _ = model.call("backup")
                            model.refresh()
                            model.showToast(model.t("saved"), tone: .success)
                        }
                    }
                    if model.backups.isEmpty {
                        SettingsCard {
                            Mix(text: model.t("empty"), size: 13, color: C.muted)
                                .frame(maxWidth: .infinity)
                                .padding(18)
                        }
                    } else {
                        SettingsCard {
                            ForEach(Array(model.backups.enumerated()), id: \.offset) { index, item in
                                if index > 0 { SettingsDivider(inset: 58) }
                                backupRow(item)
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

    func backupRow(_ item: [String: Any]) -> some View {
        let id = item["id"] as? String ?? ""
        let name = item["name"] as? String ?? id
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Mix(text: name, size: 15, weight: .semibold)
                Mix(text: id, size: 11, color: C.muted).lineLimit(1)
            }
            Spacer()
            SettingsChipButton(title: model.t("restore")) {
                _ = model.call("restore", ["id": id])
                model.refresh()
                model.showToast(model.t("imported"), tone: .success)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
