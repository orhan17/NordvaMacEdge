import AppKit

let arguments = CommandLine.arguments
Log.traceFrames = arguments.contains("--trace")
Log.isEnabled = arguments.contains("--debug") || Log.traceFrames

if arguments.contains("--check") {
    exit(SelfCheck.run())
}

let demoHUD = arguments.contains("--hud-demo")
let snapshotPath = arguments.firstIndex(of: "--settings-snapshot").flatMap {
    arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
}

// A second copy would handle every gesture twice.
if !demoHUD, snapshotPath == nil,
   let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
    print("NordvaMacEdge is already running")
    exit(0)
}

let application = NSApplication.shared
let appDelegate = AppDelegate(demoHUD: demoHUD, snapshotPath: snapshotPath)
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
