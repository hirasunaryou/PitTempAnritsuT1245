//
//  TR4ACRC.swift
//  PitTemp
//
//  Utility: CRC16(XMODEM) helper dedicated to TR4A/TR45 SOH frames.
//  The TR4A BLE spec labels the CRC as “CCITT” but the concrete parameters
//  match CRC-16/XMODEM (poly 0x1021, init 0x0000, no reflection, no final XOR)
//  and the result is sent big-endian.
//

import Foundation

enum TR4ACRC {
    /// Calculates CRC-16/XMODEM for a given payload.
    /// - Parameters:
    ///   - data: Bytes from SOH (0x01) through the last data byte. CRC bytes are not included.
    /// - Returns: Big-endian CRC16 value (callers append high byte then low byte).
    static func xmodem(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0x0000 // XMODEM uses 0x0000, not 0xFFFF (CCITT-FALSE)
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }
        return crc
    }
}
