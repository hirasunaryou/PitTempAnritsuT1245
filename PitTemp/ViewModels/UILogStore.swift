import Foundation
import SwiftUI

@MainActor
final class UILogStore: ObservableObject, UILogPublishing {
    @Published private(set) var entries: [UILogEntry] = []
    private let maxEntries = 200

    func publish(_ entry: UILogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
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
