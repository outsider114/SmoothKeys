import AppKit

enum LaunchMode {
    case ui
    case agent

    static var current: LaunchMode {
        CommandLine.arguments.contains("--agent") ? .agent : .ui
    }
}

enum RelaunchController {
    static func launchAgent() {
        launch(arguments: ["--agent"])
    }

    static func launchUI() {
        launch(arguments: [])
    }

    private static func launch(arguments: [String]) {
        let bundlePath = Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundlePath] + (arguments.isEmpty ? [] : ["--args"] + arguments)
        do {
            try process.run()
        } catch {
            NSLog("SmoothKeys relaunch failed: \(error.localizedDescription)")
        }
    }
}
