import SwiftUI

struct AboutView: View {
    @EnvironmentObject var model: Model
    var body: some View {
        sub(model.t("about")) {
            VStack(spacing: 16) {
                SettingsCard {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle().fill(C.cyan.opacity(0.14)).frame(width: 64, height: 64)
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(C.cyan)
                        }
                        Mix(text: model.t("app"), size: 22, weight: .bold)
                        Mix(
                            text: model.fa
                                ? "کلاینت دسکتاپ با همان چیدمان V2Box. کانفیگ‌ها روی همین مک می‌مانند."
                                : "A desktop client with the same V2Box layout. Configs stay on this Mac.",
                            size: 14,
                            color: C.muted
                        )
                        .multilineTextAlignment(.center)
                        if let core = model.runtime["core"] as? String, !core.isEmpty {
                            Mix(text: core, size: 12, color: C.muted.opacity(0.9))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                }
                Spacer()
            }
            .padding(.horizontal, PageLayout.horizontal)
            .padding(.top, 8)
            .padding(.bottom, PageLayout.bottom + PageLayout.tabBarClearance)
        }
    }
}
