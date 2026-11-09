import AppKit

let arguments = CommandLine.arguments
Log.isEnabled = arguments.contains("--debug")

// Без окна и трекпада: проверить, что системные вызовы вообще работают на этой macOS.
if arguments.contains("--check") {
    exit(SelfCheck.run())
}

// Две копии обработали бы один жест дважды, и громкость менялась бы вдвое быстрее.
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
    print("NordvaMacEdge уже запущен")
    exit(0)
}

let application = NSApplication.shared
let appDelegate = AppDelegate(demoHUD: arguments.contains("--hud-demo"))
application.delegate = appDelegate
application.setActivationPolicy(.accessory) // без иконки в Dock
application.run()
