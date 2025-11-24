import Foundation

/// Responsible for generating human-friendly session identifiers that still stay unique.
/// This keeps the original UUID for machine references while adding a short string that
/// operators can read during debugging (e.g. in history lists or CSV files).
struct SessionIdentifierFormatter {
    /// Compose a readable session label like `20240605-142310_IPHONE-1A2B_X7K9`.
    /// - Parameters:
    ///   - createdAt: Timestamp used to order sessions chronologically.
    ///   - device: Device identity (name + vendor ID) to embed the source phone/tablet.
    ///   - seed: UUID seed to derive a stable random-ish suffix. Using the UUID keeps
    ///     the suffix deterministic for the same session on import/export.
    /// - Returns: A short, human-parsable identifier.
    static func makeReadableID(createdAt: Date, device: DeviceIdentity, seed: UUID) -> String {
        let stamp = readableDateFormatter.string(from: createdAt)
        let deviceTag = deviceSlug(from: device)
        let suffix = randomSuffix(from: seed)
        return "\(stamp)_\(deviceTag)_\(suffix)"
    }

    /// A fallback when no device information is available (rare during legacy decode).
    static func makeReadableID(createdAt: Date, deviceName: String?, deviceID: String?, seed: UUID) -> String {
        let identity = DeviceIdentity(
            id: deviceID ?? "", // empty is acceptable; slug builder will handle it
            name: deviceName ?? ""
        )
        return makeReadableID(createdAt: createdAt, device: identity, seed: seed)
    }

    // MARK: - Private helpers

    /// Formatter dedicated to session label date strings.
    private static let readableDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    /// Build a short device slug from the device name and vendor ID.
    /// The goal is to make it obvious which handset produced the session
    /// without leaking overly long identifiers into the UI.
    private static func deviceSlug(from device: DeviceIdentity) -> String {
        // Prefer a cleaned-up device name; fall back to a trimmed vendor ID prefix.
        let cleanName = slug(from: device.name, limit: 12)
        let idSuffix = slug(from: device.id.replacingOccurrences(of: "-", with: ""), limit: 6)

        switch (cleanName.isEmpty, idSuffix.isEmpty) {
        case (false, false):
            return "\(cleanName)-\(idSuffix)"
        case (false, true):
            return cleanName
        case (true, false):
            return idSuffix
        default:
            return "DEVICE"
        }
    }

    /// Derive a deterministic-but-obfuscated suffix from the UUID so that
    /// the readable ID stays consistent across exports/imports.
    private static func randomSuffix(from seed: UUID, length: Int = 4) -> String {
        let base = seed.uuidString.replacingOccurrences(of: "-", with: "")
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var result = ""
        // Walk the UUID string in steps to spread entropy.
        for idx in stride(from: 0, to: min(base.count, length * 2), by: 2) {
            let hexPair = base.dropFirst(idx).prefix(2)
            let value = Int(hexPair, radix: 16) ?? 0
            result.append(alphabet[value % alphabet.count])
            if result.count == length { break }
        }
        return result
    }

    /// Sanitize arbitrary strings (device names, vendor IDs) into short ASCII slugs.
    private static func slug(from raw: String, limit: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let replaced = trimmed.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
        let deduped = replaced.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        let cleaned = deduped.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if cleaned.count <= limit { return cleaned.uppercased() }
        let index = cleaned.index(cleaned.startIndex, offsetBy: limit)
        return String(cleaned[..<index]).uppercased()
    }
}
