import SwiftUI

enum ToastTone {
    case info, success, warning, error
}

struct AppToastItem: Equatable {
    let id = UUID()
    var text: String
    var tone: ToastTone
}
