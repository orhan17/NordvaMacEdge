import AppKit

let arguments = CommandLine.arguments
Log.isEnabled = arguments.contains("--debug")

if arguments.contains("--check") {
    exit(SelfCheck.run())
}

// A second copy would handle every gesture twice.
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
    print("NordvaMacEdge is already running")
    exit(0)
}

let application = NSApplication.shared
let appDelegate = AppDelegate(demoHUD: arguments.contains("--hud-demo"))
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
