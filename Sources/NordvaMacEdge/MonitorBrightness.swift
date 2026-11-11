import CoreGraphics
import Foundation
import IOKit
import NordvaMacEdgeCore

/// Third-party monitors over DDC/CI. On Apple silicon the I2C channel of the display cable is
/// reached through the private IOAVService functions in IOKit; Intel Macs are not supported.
final class MonitorBrightness: LevelControl {
    /// Writes return in ~4 ms, but monitors silently drop commands that come faster than this.
    let writeInterval: TimeInterval = 0.04
    let repeatsLastWrite = true
    /// A DDC read takes ~65 ms, so a recent value is reused instead of asking the monitor again.
    var cacheLifetime: TimeInterval = 60

    private let service: CFTypeRef
    private let lock = NSLock()
    private var maximum = 100
    private var known: (level: Float, at: TimeInterval)?

    init?(display: CGDirectDisplayID) {
        guard let service = DDC.service(for: display) else { return nil }
        self.service = service
    }

    func read() -> Float? {
        lock.withLock {
            let now = ProcessInfo.processInfo.systemUptime
            if let known, now - known.at < cacheLifetime { return known.level }
            guard let reply = DDC.read(service, code: DDCPacket.brightness) else { return nil }
            maximum = reply.maximum
            let level = min(1, Float(reply.current) / Float(reply.maximum))
            known = (level, now)
            return level
        }
    }

    @discardableResult
    func write(_ level: Float) -> Bool {
        lock.withLock {
            let value = Int((level * Float(maximum)).rounded())
            guard DDC.write(service, packet: DDCPacket.set(DDCPacket.brightness, value: value)) else { return false }
            known = (level, ProcessInfo.processInfo.systemUptime)
            return true
        }
    }
}

private enum DDC {
    private typealias CreateFunction = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias ReadFunction = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    private typealias WriteFunction = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeRawPointer, UInt32) -> IOReturn
    private typealias InfoFunction = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?

    private static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    private static let create = dlsym(iokit, "IOAVServiceCreateWithService").map {
        unsafeBitCast($0, to: CreateFunction.self)
    }
    private static let readI2C = dlsym(iokit, "IOAVServiceReadI2C").map { unsafeBitCast($0, to: ReadFunction.self) }
    private static let writeI2C = dlsym(iokit, "IOAVServiceWriteI2C").map { unsafeBitCast($0, to: WriteFunction.self) }
    private static let displayInfo = dlsym(
        dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_NOW),
        "CoreDisplay_DisplayCreateInfoDictionary"
    ).map { unsafeBitCast($0, to: InfoFunction.self) }

    private static let monitorAddress: UInt32 = 0x37
    private static let hostAddress: UInt32 = 0x51

    /// CoreDisplay gives the registry path of the framebuffer behind a display. In the registry
    /// each framebuffer is followed by the DCPAVServiceProxy of the same port.
    static func service(for display: CGDirectDisplayID) -> CFTypeRef? {
        guard let create,
              let info = displayInfo?(display)?.takeRetainedValue() as? [String: Any],
              let location = info["IODisplayLocation"] as? String
        else { return nil }

        var iterator = io_iterator_t()
        guard IORegistryCreateIterator(
            kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var framebuffer = ""
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var name = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &name)
            switch String(cString: name) {
            case "IOMobileFramebufferShim", "AppleCLCD2":
                var path = [CChar](repeating: 0, count: 512)
                IORegistryEntryGetPath(entry, kIOServicePlane, &path)
                framebuffer = String(cString: path)
            case "DCPAVServiceProxy" where framebuffer == location:
                let place = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String
                return place == "External" ? create(kCFAllocatorDefault, entry)?.takeRetainedValue() : nil
            default:
                break
            }
        }
        return nil
    }

    static func write(_ service: CFTypeRef, packet: [UInt8]) -> Bool {
        writeI2C?(service, monitorAddress, hostAddress, packet, UInt32(packet.count)) == kIOReturnSuccess
    }

    static func read(_ service: CFTypeRef, code: UInt8) -> (current: Int, maximum: Int)? {
        guard let readI2C else { return nil }
        for _ in 0..<2 {
            guard write(service, packet: DDCPacket.get(code)) else { continue }
            usleep(40_000) // the monitor needs time to prepare the reply
            var reply = [UInt8](repeating: 0, count: 12)
            if readI2C(service, monitorAddress, hostAddress, &reply, UInt32(reply.count)) == kIOReturnSuccess,
               let value = DDCPacket.parse(reply, code: code) {
                return value
            }
            usleep(40_000)
        }
        return nil
    }
}
