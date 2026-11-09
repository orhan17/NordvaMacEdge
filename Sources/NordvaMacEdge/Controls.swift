import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation

enum LevelKind {
    case volume
    case brightness
}

protocol LevelControl {
    func read() -> Float?
    @discardableResult func write(_ level: Float) -> Bool
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

/// Built-in display only. There is no public API for brightness, so this uses the private DisplayServices.
final class BrightnessControl: LevelControl {
    private typealias GetFunction = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (UInt32, Float) -> Int32

    private let getBrightness: GetFunction?
    private let setBrightness: SetFunction?

    init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        let handle = dlopen(path, RTLD_NOW)
        getBrightness = dlsym(handle, "DisplayServicesGetBrightness").map {
            unsafeBitCast($0, to: GetFunction.self)
        }
        setBrightness = dlsym(handle, "DisplayServicesSetBrightness").map {
            unsafeBitCast($0, to: SetFunction.self)
        }
    }

    private func builtInDisplay() -> CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    func read() -> Float? {
        guard let getBrightness, let display = builtInDisplay() else { return nil }
        var level: Float = 0
        return getBrightness(display, &level) == 0 ? level : nil
    }

    @discardableResult
    func write(_ level: Float) -> Bool {
        guard let setBrightness, let display = builtInDisplay() else { return false }
        return setBrightness(display, level) == 0
    }
}
