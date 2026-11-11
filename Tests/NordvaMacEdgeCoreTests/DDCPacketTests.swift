import Testing
@testable import NordvaMacEdgeCore

@Test func setBrightnessPacket() {
    #expect(DDCPacket.set(DDCPacket.brightness, value: 98) == [0x84, 0x03, 0x10, 0x00, 0x62, 0xCA])
}

@Test func getBrightnessPacket() {
    #expect(DDCPacket.get(DDCPacket.brightness) == [0x82, 0x01, 0x10, 0xAC])
}

@Test func parsesARealReply() {
    let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x62, 0xA2, 0x3B]
    let value = DDCPacket.parse(reply, code: DDCPacket.brightness)
    #expect(value?.current == 98)
    #expect(value?.maximum == 100)
}

@Test func rejectsUnsupportedCodesAndBrokenReplies() {
    let unsupported: [UInt8] = [0x6E, 0x88, 0x02, 0x01, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    #expect(DDCPacket.parse(unsupported, code: DDCPacket.brightness) == nil)
    let otherCode: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00, 0x00]
    #expect(DDCPacket.parse(otherCode, code: DDCPacket.brightness) == nil)
    #expect(DDCPacket.parse([0x6E, 0x88, 0x02], code: DDCPacket.brightness) == nil)
    #expect(DDCPacket.parse([UInt8](repeating: 0, count: 12), code: DDCPacket.brightness) == nil)
}
