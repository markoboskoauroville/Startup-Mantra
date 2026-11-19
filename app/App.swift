import Cocoa
import SwiftUI
import ServiceManagement

let VERSION = 1

/* App Targets and Bundle Identifiers */

enum TargetApp: String, CaseIterable, Identifiable, Sendable {
    case voiceToText = "Voice to Text (Mantra)"
    case speechify = "Speechify"

    var id: String { rawValue }

    var primaryBundleId: String {
        switch self {
        case .voiceToText:
            return "com.mantra.voicetotext"
        case .speechify:
            return "com.cliffweitzman.speechifymacagent"
        }
    }

    var fallbackAppNames: [String] {
        switch self {
        case .voiceToText:
            return ["Voice to Text (Mantra).app", "Vox to Txt (Mantra).app"]
        case .speechify:
            return ["Speechify Voice AI.app", "Speechify.app"]
        }
    }

    var other: TargetApp {
        switch self {
        case .voiceToText: return .speechify
        case .speechify: return .voiceToText
        }
    }
}

/* Decision Logic */

enum AppAction: Equatable {
    case terminateAndLaunch(toTerminate: TargetApp, toLaunch: TargetApp)
    case launchOnly(toLaunch: TargetApp)
    case terminateOnly(toTerminate: TargetApp)
    case notInstalled(target: TargetApp)
    case alreadyRunning(target: TargetApp)
}

func decideAction(
    target: TargetApp,
    isTargetRunning: Bool,
    isOtherRunning: Bool,
    isTargetInstalled: Bool
) -> AppAction {
    if !isTargetInstalled {
        return .notInstalled(target: target)
    }
    if isOtherRunning && !isTargetRunning {
        return .terminateAndLaunch(toTerminate: target.other, toLaunch: target)
    } else if isOtherRunning && isTargetRunning {
        return .terminateOnly(toTerminate: target.other)
    } else if !isTargetRunning {
        return .launchOnly(toLaunch: target)
    } else {
        return .alreadyRunning(target: target)
    }
}

/* App State */

@MainActor
final class AppState: ObservableObject {
    @Published var selectedApp: TargetApp {
        didSet {
            UserDefaults.standard.set(selectedApp.rawValue, forKey: "selectedApp")
        }
    }
    @Published var startAtLogin: Bool = false
    @Published var loginStatusDescription: String = "Checking..."
    @Published var statusMessage: String = "Ready"
    @Published var notInstalledWarning: String? = nil

    init() {
        if let saved = UserDefaults.standard.string(forKey: "selectedApp"),
           let app = TargetApp(rawValue: saved) {
            self.selectedApp = app
        } else {
            self.selectedApp = .voiceToText
        }
    }

    func syncLoginItem() {
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            startAtLogin = true
            loginStatusDescription = "Enabled"
        case .notRegistered:
            startAtLogin = false
            loginStatusDescription = "Not registered"
        case .requiresApproval:
            startAtLogin = false
            loginStatusDescription = "Requires approval in System Settings"
        case .notFound:
            startAtLogin = false
            loginStatusDescription = "Not found"
        @unknown default:
            startAtLogin = false
            loginStatusDescription = "Unknown status"
        }
    }

    func setStartAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                startAtLogin = true
                loginStatusDescription = "Enabled"
            } else {
                try SMAppService.mainApp.unregister()
                startAtLogin = false
                loginStatusDescription = "Disabled"
            }
        } catch {
            loginStatusDescription = "Error: \(error.localizedDescription)"
        }
    }

    func findAppURL(for app: TargetApp) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.primaryBundleId) {
            return url
        }
        let fm = FileManager.default
        let searchDirs = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        for dir in searchDirs {
            for name in app.fallbackAppNames {
                let candidate = dir.appendingPathComponent(name)
                if fm.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    func isRunning(_ app: TargetApp) -> Bool {
        return !NSRunningApplication.runningApplications(withBundleIdentifier: app.primaryBundleId).isEmpty
    }

    func applySelection() {
        let target = selectedApp
        let other = target.other

        let targetRunning = isRunning(target)
        let otherRunning = isRunning(other)
        let targetURL = findAppURL(for: target)
        let targetInstalled = (targetURL != nil)

        let action = decideAction(
            target: target,
            isTargetRunning: targetRunning,
            isOtherRunning: otherRunning,
            isTargetInstalled: targetInstalled
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeString = formatter.string(from: Date())

        switch action {
        case .notInstalled(let missing):
            notInstalledWarning = "\(missing.rawValue) is not installed on this Mac."
            statusMessage = "[\(timeString)] \(missing.rawValue) not found"

        case .alreadyRunning(let app):
            notInstalledWarning = nil
            statusMessage = "[\(timeString)] \(app.rawValue) is already running"

        case .terminateOnly(let toKill):
            notInstalledWarning = nil
            let killTarget = toKill
            terminateApp(killTarget) { [weak self] in
                Task { @MainActor in
                    self?.statusMessage = "[\(timeString)] Killed \(killTarget.rawValue)"
                }
            }

        case .launchOnly(let toStart):
            notInstalledWarning = nil
            let startTarget = toStart
            if let url = targetURL {
                launchApp(at: url) { [weak self] success in
                    Task { @MainActor in
                        if success {
                            self?.statusMessage = "[\(timeString)] Started \(startTarget.rawValue)"
                        } else {
                            self?.statusMessage = "[\(timeString)] Failed to start \(startTarget.rawValue)"
                        }
                    }
                }
            }

        case .terminateAndLaunch(let toKill, let toStart):
            notInstalledWarning = nil
            let killTarget = toKill
            let startTarget = toStart
            let urlToLaunch = targetURL
            terminateApp(killTarget) { [weak self] in
                guard let url = urlToLaunch else { return }
                self?.launchApp(at: url) { success in
                    Task { @MainActor in
                        if success {
                            self?.statusMessage = "[\(timeString)] Killed \(killTarget.rawValue), started \(startTarget.rawValue)"
                        } else {
                            self?.statusMessage = "[\(timeString)] Killed \(killTarget.rawValue), failed to start \(startTarget.rawValue)"
                        }
                    }
                }
            }
        }
    }

    private nonisolated func terminateApp(_ app: TargetApp, completion: @Sendable @escaping () -> Void) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.primaryBundleId)
        if running.isEmpty {
            completion()
            return
        }
        for item in running {
            item.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            for item in running {
                if !item.isTerminated {
                    item.forceTerminate()
                }
            }
            completion()
        }
    }

    private nonisolated func launchApp(at url: URL, completion: @Sendable @escaping (Bool) -> Void) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            completion(error == nil)
        }
    }
}

/* SwiftUI View */

struct ContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Default Voice App")
                    .font(.headline)
                Picker("", selection: $state.selectedApp) {
                    ForEach(TargetApp.allCases) { app in
                        Text(app.rawValue).tag(app)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: state.selectedApp) { _ in
                    state.applySelection()
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start at login")
                        .font(.body)
                    Text("Status: \(state.loginStatusDescription)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { state.startAtLogin },
                    set: { state.setStartAtLogin($0) }
                ))
                .toggleStyle(.switch)
            }

            Divider()

            if let warning = state.notInstalledWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(warning)
                        .foregroundColor(.orange)
                        .font(.callout)
                }
            }

            Spacer()

            HStack {
                Text("Last action:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(state.statusMessage)
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 240)
    }
}

/* App Delegate & Entry Point */

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private let appState = AppState()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView(state: appState)
        let hostingController = NSHostingController(rootView: contentView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Startup (Mantra)"
        win.setFrameAutosaveName("StartupMantraMainWindow")
        win.center()
        win.contentViewController = hostingController
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        self.window = win

        appState.syncLoginItem()
        appState.applySelection()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}
