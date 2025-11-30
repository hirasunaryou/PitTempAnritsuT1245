import Foundation

struct UILogEntry: Identifiable, Equatable {
    enum Level: String {
        case info
        case success
        case warning
        case error
    }

    enum Category: String {
        case general
        case autosave
        case ble
    }

    let id = UUID()
    let message: String
    let level: Level
    let category: Category
    let createdAt: Date

    init(message: String,
         level: Level = .info,
         category: Category = .general,
         createdAt: Date = Date()) {
        self.message = message
        self.level = level
        self.category = category
        self.createdAt = createdAt
    }
}

protocol UILogPublishing: AnyObject {
    func publish(_ entry: UILogEntry)
}
