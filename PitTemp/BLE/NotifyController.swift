import Foundation
import Combine

/// Notify受信処理とメトリクス計測を担当
final class NotifyController {
    private let parser: TemperaturePacketParser
    private let emit: (TemperatureFrame) -> Void
    private let mainQueue: DispatchQueue

    private var notifyCountBG: Int = 0
    private var prevNotifyAt: Date?
    private var emaInterval: Double?
    private let emaAlpha = 0.25

    var onCountUpdate: ((Int) -> Void)?
    var onHzUpdate: ((Double) -> Void)?

    init(parser: TemperaturePacketParser,
         mainQueue: DispatchQueue = .main,
         emit: @escaping (TemperatureFrame) -> Void) {
        self.parser = parser
        self.mainQueue = mainQueue
        self.emit = emit
    }

    func handleNotification(_ data: Data) {
        notifyCountBG &+= 1
        mainQueue.async { self.onCountUpdate?(self.notifyCountBG) }

        let now = Date()
        if let prev = prevNotifyAt {
            let dt = now.timeIntervalSince(prev)
            if dt > 0 {
                if let ema = emaInterval {
                    emaInterval = ema * (1 - emaAlpha) + dt * emaAlpha
                } else {
                    emaInterval = dt
                }
                if let iv = emaInterval, iv > 0 {
                    let hz = 1.0 / iv
                    mainQueue.async { self.onHzUpdate?(hz) }
                }
            }
        }
        prevNotifyAt = now

        parser.parseFrames(data).forEach(emit)
    }
}
