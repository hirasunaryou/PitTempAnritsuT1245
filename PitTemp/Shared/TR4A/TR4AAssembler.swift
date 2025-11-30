import Foundation

/// TR4A の Notify フラグメントを 1 フレームに束ねるためのシンプルなバッファ。
/// - Attention: Notify が 20B で分割される場合に備え、CRC と期待長が揃うまで蓄積する。
final class TR4AAssembler {
    private var buffer = Data()

    /// フラグメントを追加し、デコード可能なフレームを返す。複数含まれる場合もあるため配列で返却。
    func append(_ data: Data) -> [TR4AProtocol.Frame] {
        buffer.append(data)
        var frames: [TR4AProtocol.Frame] = []

        while buffer.count >= 7 { // SOH(1)+CMD(1)+SEQ(1)+LEN(2)+CRC(2)
            guard buffer[0] == 0x01 else {
                // ノイズを捨てるため、SOH が現れるまで先頭を削る。
                buffer.removeFirst()
                continue
            }
            let length = UInt16(buffer[3]) | (UInt16(buffer[4]) << 8)
            let totalLength = 5 + Int(length) + 2
            if buffer.count < totalLength { break }

            let candidate = buffer.prefix(totalLength)
            if let frame = TR4AProtocol.decode(candidate) {
                frames.append(frame)
                buffer.removeFirst(totalLength)
            } else {
                // CRC 不一致時は先頭を1Bずつ捨ててリカバリー。
                buffer.removeFirst()
            }
        }
        return frames
    }

    /// 明示的にバッファをリセットしたい場合に呼ぶ。
    func reset() { buffer.removeAll(keepingCapacity: false) }
}
