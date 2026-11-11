import AppKit
import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation

enum LevelKind {
    case volume
    case brightness
}

protocol LevelControl: AnyObject {
    func read() -> Float?
    @discardableResult func write(_ level: Float) -> Bool
    /// The pause after each write. Monitors drop DDC commands that come too fast.
    var writeInterval: TimeInterval { get }
    /// Monitors now and then drop a DDC command, so the final value is sent again once the finger stops.
    var repeatsLastWrite: Bool { get }
}

extension LevelControl {
    var writeInterval: TimeInterval { 0 }
    var repeatsLastWrite: Bool { false }
}

final class VolumeControl: LevelControl {
    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private func outputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    var isMuted: Bool {
        guard let device = outputDevice(), AudioObjectHasProperty(device, &muteAddress) else { return false }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &muted)
        return status == noErr && muted != 0
    }

    func read() -> Float? {
        guard let device = outputDevice(), AudioObjectHasProperty(device, &volumeAddress) else { return nil }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &volume) == noErr else {
            return nil
        }
        return isMuted ? 0 : volume
    }

    func toggleMute() -> Bool? {
        guard let device = outputDevice(), AudioObjectHasProperty(device, &muteAddress) else { return nil }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &muteAddress, &settable) == noErr, settable.boolValue else {
            return nil
        }
        var muted: UInt32 = isMuted ? 0 : 1
        let status = AudioObjectSetPropertyData(
            device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &muted
        )
        return status == noErr ? muted != 0 : nil
    }

    @discardableResult
    func write(_ level: Float) -> Bool {
        guard let device = outputDevice(), AudioObjectHasProperty(device, &volumeAddress) else { return false }
        var volume = Float32(level)
        let status = AudioObjectSetPropertyData(
            device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume
        )
        if status == noErr, level > 0, isMuted, AudioObjectHasProperty(device, &muteAddress) {
            var unmuted: UInt32 = 0
            AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &unmuted)
        }
        return status == noErr
    }
}

/// Built-in and Apple displays. There is no public API for brightness, so this uses the private DisplayServices.
final class DisplayBrightness: LevelControl {
    private typealias GetFunction = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (UInt32, Float) -> Int32
    private typealias CanChangeFunction = @convention(c) (UInt32) -> Bool

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW
    )
    private static let getBrightness = dlsym(handle, "DisplayServicesGetBrightness").map {
        unsafeBitCast($0, to: GetFunction.self)
    }
    private static let setBrightness = dlsym(handle, "DisplayServicesSetBrightness").map {
        unsafeBitCast($0, to: SetFunction.self)
    }
    private static let canChangeBrightness = dlsym(handle, "DisplayServicesCanChangeBrightness").map {
        unsafeBitCast($0, to: CanChangeFunction.self)
    }

    static func supports(_ display: CGDirectDisplayID) -> Bool {
        canChangeBrightness?(display) ?? (CGDisplayIsBuiltin(display) != 0)
    }

    let display: CGDirectDisplayID

    init(display: CGDirectDisplayID) {
        self.display = display
    }

    func read() -> Float? {
        guard let getBrightness = Self.getBrightness else { return nil }
        var level: Float = 0
        return getBrightness(display, &level) == 0 ? level : nil
    }

    @discardableResult
    func write(_ level: Float) -> Bool {
        guard let setBrightness = Self.setBrightness else { return false }
        return setBrightness(display, level) == 0
    }
}

/// The display under the pointer: DisplayServices for built-in and Apple displays, DDC for other
/// monitors, and the built-in display when the monitor does not answer DDC.
final class Brightness {
    private let lock = NSLock()
    private var monitors: [CGDirectDisplayID: MonitorBrightness] = [:]
    private var silent: Set<CGDirectDisplayID> = []
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.lock.withLock {
                self?.monitors = [:]
                self?.silent = []
            }
        }
    }

    func underPointer() -> (control: LevelControl, level: Float?) {
        if let display = Self.displayUnderPointer() {
            if DisplayBrightness.supports(display) {
                let control = DisplayBrightness(display: display)
                return (control, control.read())
            }
            if let monitor = monitor(for: display) {
                if let level = monitor.read() {
                    return (monitor, level)
                }
                lock.withLock {
                    monitors[display] = nil
                    silent.insert(display)
                }
            }
        }
        let builtIn = DisplayBrightness(display: Self.builtInDisplay() ?? CGMainDisplayID())
        return (builtIn, builtIn.read())
    }

    private func monitor(for display: CGDirectDisplayID) -> MonitorBrightness? {
        lock.withLock {
            if silent.contains(display) { return nil }
            if let monitor = monitors[display] { return monitor }
            guard let monitor = MonitorBrightness(display: display) else {
                silent.insert(display)
                return nil
            }
            monitors[display] = monitor
            return monitor
        }
    }

    static func displayUnderPointer() -> CGDirectDisplayID? {
        guard let point = CGEvent(source: nil)?.location else { return nil }
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 else { return nil }
        return display
    }

    static func builtInDisplay() -> CGDirectDisplayID? {
        onlineDisplays().first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func onlineDisplays() -> [CGDirectDisplayID] {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }
}
