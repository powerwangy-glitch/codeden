import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: AppStore!
    var controller: NotchController!
    var settings: SettingsController!
    var onboarding: OnboardingController!
    var tailer: EventTailer!
    var quotaTimer: Timer?

    static var eventsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notch-island/events.jsonl")
    }

    static var pidURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".notch-island/run/app.pid")
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        store = AppStore()
        controller = NotchController(store: store)
        settings = SettingsController(store: store)
        onboarding = OnboardingController(store: store)
        store.openSettings = { [weak self] in self?.settings.show() }
        store.openOnboarding = { [weak self] in self?.onboarding.show() }
        controller.show()
        writePidfile()
        store.play(.startup)

        // 首次启动弹引导
        if OnboardingController.shouldShow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.onboarding.show() }
        }

        // 额度：启动读一次 + 每 30s 刷新
        refreshQuota()
        quotaTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshQuota() }
        }

        // 实时事件链路
        tailer = EventTailer(url: Self.eventsURL) { event in
            MainActor.assumeIsolated { self.store.ingest(event) }
        }
        tailer.start()

        // 仅首次体验（未完成引导）时载入演示数据；日常使用空着就显示「都在休息」
        if OnboardingController.shouldShow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                if self.store.sessions.isEmpty {
                    self.store.loadDemo()
                    self.controller.show()
                }
            }
        }
    }

    private func refreshQuota() {
        store.quotas = QuotaReader.readAll()
    }

    private func writePidfile() {
        let url = Self.pidURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "\(ProcessInfo.processInfo.processIdentifier)".write(to: url, atomically: true, encoding: .utf8)
    }

    func applicationWillTerminate(_ note: Notification) {
        try? FileManager.default.removeItem(at: Self.pidURL)
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)   // 不在 Dock 显示
app.run()
