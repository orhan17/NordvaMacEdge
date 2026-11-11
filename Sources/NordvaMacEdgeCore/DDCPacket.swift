/// DDC/CI messages for VCP codes, the protocol monitors speak over the display cable.
/// Brightness is VCP code 0x10.
public enum DDCPacket {
    public static let brightness: UInt8 = 0x10

    /// Set VCP feature: opcode 0x03, code, value high byte, value low byte.
    public static func set(_ code: UInt8, value: Int) -> [UInt8] {
        framed([0x03, code, UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    /// Get VCP feature: opcode 0x01, code.
    public static func get(_ code: UInt8) -> [UInt8] {
        framed([0x01, code])
    }

    /// The reply starts with the monitor's address 0x6E and a length byte, then opcode 0x02,
    /// result (0 when the code is supported), the code, its type, maximum and current value.
    public static func parse(_ reply: [UInt8], code: UInt8) -> (current: Int, maximum: Int)? {
        guard reply.count >= 10, reply[2] == 0x02, reply[3] == 0x00, reply[4] == code else { return nil }
        let maximum = Int(reply[6]) << 8 | Int(reply[7])
        let current = Int(reply[8]) << 8 | Int(reply[9])
        guard maximum > 0 else { return nil }
        return (current, maximum)
    }

    /// A length byte with the high bit set, the payload, and an XOR checksum that also covers
    /// the monitor's address 0x6E and the host's address 0x51.
    private static func framed(_ payload: [UInt8]) -> [UInt8] {
        let bytes = [0x80 | UInt8(payload.count)] + payload
        return bytes + [bytes.reduce(0x6E ^ 0x51, ^)]
    }
}
