import CMultitouch
import Foundation
import NordvaMacEdgeCore

private typealias ContactCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<MTTouch>?, Int32, Double, Int32
) -> Int32

private struct MultitouchAPI {
    typealias CreateDefault = @convention(c) () -> UnsafeMutableRawPointer?
    typealias Register = @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
    typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Int32
    typealias Release = @convention(c) (UnsafeMutableRawPointer) -> Void
    typealias Dimensions = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32

    let createDefault: CreateDefault
    let register: Register
    let unregister: Register
    let start: Start
    let stop: Stop
    let release: Release
    let dimensions: Dimensions?

    init?() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW),
              let createDefault = dlsym(handle, "MTDeviceCreateDefault"),
              let register = dlsym(handle, "MTRegisterContactFrameCallback"),
              let unregister = dlsym(handle, "MTUnregisterContactFrameCallback"),
              let start = dlsym(handle, "MTDeviceStart"),
              let stop = dlsym(handle, "MTDeviceStop"),
              let release = dlsym(handle, "MTDeviceRelease")
        else { return nil }
        self.createDefault = unsafeBitCast(createDefault, to: CreateDefault.self)
        self.register = unsafeBitCast(register, to: Register.self)
        self.unregister = unsafeBitCast(unregister, to: Register.self)
        self.start = unsafeBitCast(start, to: Start.self)
        self.stop = unsafeBitCast(stop, to: Stop.self)
        self.release = unsafeBitCast(release, to: Release.self)
        dimensions = dlsym(handle, "MTDeviceGetSensorSurfaceDimensions").map { unsafeBitCast($0, to: Dimensions.self) }
    }
}

// A C callback cannot capture context, so the handler lives in a global.
private var frameHandler: (([TouchPoint], Double) -> Void)?

private let contactCallback: ContactCallback = { _, touches, count, timestamp, _ in
    var points: [TouchPoint] = []
    if let touches {
        points.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            let touch = touches[index]
            guard Int(touch.state) == MTTouchStateMakeTouch || Int(touch.state) == MTTouchStateTouching else {
                continue
            }
            points.append(TouchPoint(
                id: touch.identifier,
                x: Double(touch.normalized.position.x),
                y: Double(touch.normalized.position.y),
                size: Double(touch.size),
                majorAxis: Double(touch.majorAxis)
            ))
        }
    }
    frameHandler?(points, timestamp)
    return 0
}

/// Raw touches from the built-in trackpad, ~100 frames per second on a background thread.
final class TouchSource {
    private let api: MultitouchAPI
    private var device: UnsafeMutableRawPointer?

    init?(onFrame: @escaping ([TouchPoint], Double) -> Void) {
        guard let api = MultitouchAPI() else { return nil }
        self.api = api
        frameHandler = onFrame
    }

    /// Physical surface size in centimeters; the framework reports hundredths of a millimeter.
    var surfaceSize: (width: Double, height: Double)? {
        guard let device, let dimensions = api.dimensions else { return nil }
        var width: Int32 = 0
        var height: Int32 = 0
        guard dimensions(device, &width, &height) == 0, width > 0, height > 0 else { return nil }
        return (Double(width) / 1000, Double(height) / 1000)
    }

    @discardableResult
    func start() -> Bool {
        guard device == nil, let newDevice = api.createDefault() else { return device != nil }
        api.register(newDevice, contactCallback)
        let status = api.start(newDevice, 0)
        device = newDevice
        Log.debug("trackpad started, status \(status)")
        return status == 0
    }

    func stop() {
        guard let device else { return }
        api.unregister(device, contactCallback)
        _ = api.stop(device)
        api.release(device)
        self.device = nil
        Log.debug("trackpad stopped")
    }
}
