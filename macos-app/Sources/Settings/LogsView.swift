import SwiftUI

struct LogsView: View {
    @EnvironmentObject var model: Model
    @State private var text = ""
    var body: some View {
        sub(model.t("logs")) {
            ScrollView(.vertical, showsIndicators: false) {
                SettingsCard {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(C.cyan.opacity(0.14))
                                Image(systemName: "doc.text")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(C.cyan)
                            }
                            .frame(width: 40, height: 40)
                            Mix(text: model.t("empty"), size: 13, color: C.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                    } else {
                        Text(text)
                            .font(.custom("Inter", size: 12))
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, PageLayout.horizontal)
                .padding(.top, 8)
                .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .onAppear { text = (model.call("logs")["data"] as? [String: Any])?["text"] as? String ?? "" }
        }
    }
}
