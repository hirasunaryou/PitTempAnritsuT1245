// Haptics.swift
// かんたんハプティクスヘルパー（iOS標準のフィードバックAPI）

import UIKit

enum Haptics {
    static func impactLight() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func impactMedium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
