import Combine
import Foundation

@MainActor
final class LiveRuntime: ObservableObject {
    @Published private(set) var values: [String: Any] = [:]

    func replaceIfChanged(_ new: [String: Any]) {
        guard !NSDictionary(dictionary: values).isEqual(to: new) else { return }
        values = new
    }
}
