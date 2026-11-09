import CMultitouch
import Foundation
import NordvaMacEdgeCore

private typealias ContactCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<MTTouch>?, Int32, Double, Int32
) -> Int32

/// Функции загружаются через dlopen, а не линкуются: если Apple уберёт фреймворк,
/// приложение покажет понятную ошибку, а не упадёт при старте.
private struct MultitouchAPI {
    typealias CreateDefault = @convention(c) () -> UnsafeMutableRawPointer?
    typealias Register = @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
    typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Int32
    typealias Release = @convention(c) (UnsafeMutableRawPointer) -> Void

    let createDefault: CreateDefault
    let register: Register
    let unregister: Register
    let start: Start
    let stop: Stop
    let release: Release

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
    }
}

// C-колбэк не может ничего захватить, поэтому обработчик лежит в глобальной переменной.
private var frameHandler: (([TouchPoint], Double) -> Void)?

private let contactCallback: ContactCallback = { _, touches, count, timestamp, _ in
    var points: [TouchPoint] = []
    if let touches {
        points.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            let touch = touches[index]
            // Палец, который завис над поверхностью или только что поднялся, не считаем.
            guard Int(touch.state) == MTTouchStateMakeTouch || Int(touch.state) == MTTouchStateTouching else {
                continue
            }
            points.append(TouchPoint(
                id: touch.identifier,
                x: Double(touch.normalized.position.x),
                y: Double(touch.normalized.position.y)
            ))
        }
    }
    frameHandler?(points, timestamp)
    return 0
}

/// Сырые касания встроенного трекпада. Колбэк приходит примерно 100 раз в секунду
/// на чужом потоке, поэтому внутри него нельзя делать ничего долгого.
final class TouchSource {
    private let api: MultitouchAPI
    private var device: UnsafeMutableRawPointer?

    /// `onFrame` получает пальцы и время кадра в секундах.
    init?(onFrame: @escaping ([TouchPoint], Double) -> Void) {
        guard let api = MultitouchAPI() else { return nil }
        self.api = api
        frameHandler = onFrame
    }

    @discardableResult
    func start() -> Bool {
        guard device == nil, let newDevice = api.createDefault() else { return device != nil }
        api.register(newDevice, contactCallback)
        let status = api.start(newDevice, 0)
        device = newDevice
        Log.debug("трекпад запущен, статус \(status)")
        return status == 0
    }

    func stop() {
        guard let device else { return }
        api.unregister(device, contactCallback)
        _ = api.stop(device)
        api.release(device)
        self.device = nil
        Log.debug("трекпад остановлен")
    }
}
