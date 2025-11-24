import Foundation
import SwiftUI

@MainActor
final class UILogStore: ObservableObject, UILogPublishing {
    @Published private(set) var entries: [UILogEntry] = []
    private let maxEntries = 200

    nonisolated func publish(_ entry: UILogEntry) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func add(message: String,
             level: UILogEntry.Level = .info,
             category: UILogEntry.Category = .general) {
        publish(UILogEntry(message: message, level: level, category: category))
    }

    func clear() {
        entries.removeAll()
    }
}
