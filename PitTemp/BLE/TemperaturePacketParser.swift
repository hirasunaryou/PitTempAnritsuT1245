//  TemperaturePacketParser.swift
//  PitTemp
//  Anritsu試作機: 先頭4バイトが 0C 00 00 00 / 00 00 00 00 の両方に対応

import Foundation

final class TemperaturePacketParser {
    private var buf = Data()

    private let frameLen = 20
    private let headerV1: [UInt8] = [0x00, 0x00, 0x00, 0x00]
    private let headerV2: [UInt8] = [0x0C, 0x00, 0x00, 0x00]

    func parseFrames(_ data: Data) -> [TemperatureFrame] {
        buf.append(data)
        var out: [TemperatureFrame] = []

        while true {
            guard let headIndex = findHeaderIndex() else { break }
            if headIndex > 0 { buf.removeFirst(headIndex) }
            guard buf.count >= frameLen else { break }

            let frame = Data(buf.prefix(frameLen))   // ← ここを Data に
            buf.removeFirst(frameLen)

            let idStr   = String(data: frame.subdata(in: 4..<7),  encoding: .ascii) ?? ""
            let tempStr = String(data: frame.subdata(in: 7..<13), encoding: .ascii) ?? ""

            let deviceID = Int(idStr)
            var status: TemperatureFrame.Status? = nil

            if tempStr.count == 6, let sign = tempStr.first {
                let digits = String(tempStr.dropFirst())
                if let n = Int(digits) {
                    var v = Double(n) / 10.0
                    if sign == "-" { v = -v }
                    switch (sign, n) {
                    case ("-", 32768): v = -3276.8; status = .bout
                    case ("-", 32767): v = -3276.7; status = .under
                    case ("+", 32767): v =  3276.7; status = .over
                    default: break
                    }
                    out.append(TemperatureFrame(time: Date(), deviceID: deviceID, value: v, status: status))
                }
            }
        }
        return out
    }

    private func findHeaderIndex() -> Int? {
        let bytes = [UInt8](buf)
        guard bytes.count >= 4 else { return nil }
        for i in 0...(bytes.count - 4) {
            let h = Array(bytes[i..<(i+4)])
            if h == headerV1 || h == headerV2 { return i }
        }
        return nil
    }

    func buildDATARequest() -> Data { Data([0x07,0x00,0x00,0x00]) + "DATA".data(using: .ascii)! }
    func buildTIMESet(date: Date = Date()) -> Data {
        let c = Calendar(identifier: .gregorian)
        let hh = String(format: "%02d", c.component(.hour,   from: date))
        let mm = String(format: "%02d", c.component(.minute, from: date))
        let ss = String(format: "%02d", c.component(.second, from: date))
        return Data([0x00,0x00,0x00,0x00]) + "TIME".data(using: .ascii)! +
               hh.data(using: .ascii)! + mm.data(using: .ascii)! + ss.data(using: .ascii)!
    }
}

