import SwiftUI

extension ConfigsView {

    var addMenuOverlay: some View {
        SheetBackdrop(onDismiss: { addStep = .none }) {
            SheetCard {
              VStack(alignment: .leading, spacing: 0) {
                SheetHeader(title: model.t("add"), subtitle: model.t("addHint"), close: { addStep = .none }, closeLabel: model.t("cancel"))
                HStack(spacing: 10) {
                    AddQuickTile(icon: "doc.on.clipboard", title: model.t("importClip"), hint: model.t("clipHint"), tint: C.cyan, action: importClipboard)
                    AddQuickTile(icon: "qrcode.viewfinder", title: model.t("qr"), hint: model.t("qrHint"), tint: C.speedUp, action: { addStep = .scan })
                }
                .padding(.bottom, 12)
                VStack(spacing: 0) {
                    AddActionRow(icon: "doc.text", title: model.t("clashYaml"), hint: model.t("clashYamlHint"), tint: C.ping, action: importClashFile)
                    Rectangle().fill(C.line).frame(height: 1).padding(.leading, 64)
                    AddActionRow(icon: "slider.horizontal.3", title: model.t("manual"), hint: model.t("manualHint"), tint: C.cyan, action: openManualEditor)
                    Rectangle().fill(C.line).frame(height: 1).padding(.leading, 64)
                    AddActionRow(icon: "folder", title: model.t("file"), hint: model.t("fileHint"), tint: Color(red: 0.96, green: 0.72, blue: 0.38), action: importFile)
                }
                .background(C.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(C.line, lineWidth: 1)
                )
                SheetActionButton(title: model.t("cancel"), quiet: true) { addStep = .none }
                    .padding(.top, 4)
              }
            }
        }
    }

    var filePasswordOverlay: some View {
        SheetBackdrop(onDismiss: { lockedImportB64 = nil }) {
            SheetCard {
              VStack(alignment: .leading, spacing: 0) {
                SheetHeader(title: model.t("filePassword"), subtitle: model.t("filePasswordHint"), close: { lockedImportB64 = nil }, closeLabel: model.t("cancel"))
                HStack {
                    Spacer()
                    ZStack {
                        Circle().fill(C.cyan.opacity(0.12)).frame(width: 64, height: 64)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(C.cyan)
                    }
                    Spacer()
                }
                .padding(.bottom, 16)
                V2Field(placeholder: "••••••••", text: $filePassword, latin: true, secure: true, icon: "key.fill")
                    .padding(.bottom, 14)
                SheetActionButton(title: model.t("unlockFile"), primary: true, icon: "lock.open.fill") { confirmLockedImport() }
                SheetActionButton(title: model.t("cancel"), quiet: true) { lockedImportB64 = nil }
              }
            }
        }
    }

    var addScanOverlay: some View {
        SheetBackdrop(onDismiss: { addStep = .none }) {
            SheetCard {
              VStack(alignment: .leading, spacing: 0) {
                SheetHeader(
                    title: model.t("qr"),
                    subtitle: model.t("qrPoint"),
                    back: { addStep = .menu },
                    close: { addStep = .none },
                    closeLabel: model.t("cancel")
                )
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.04, green: 0.06, blue: 0.10))
                    VStack(spacing: 8) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(C.muted.opacity(0.7))
                        Mix(text: model.t("qrPoint"), size: 12, color: C.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    ScanView { text in finishImport(text: text) }
                    LinearGradient(
                        colors: [Color.black.opacity(0.28), .clear, .clear, Color.black.opacity(0.35)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                    ScanCorners()
                }
                .frame(height: 228)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(C.cyan.opacity(0.28), lineWidth: 1)
                )
                .padding(.bottom, 14)
                SheetActionButton(title: model.t("chooseImage"), icon: "photo") { importQRImage() }
                SheetActionButton(title: model.t("cancel"), quiet: true) { addStep = .none }
              }
            }
        }
    }
}
