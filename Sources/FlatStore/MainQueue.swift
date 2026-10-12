import Foundation
import GLib

final class MainQueue {
    static let shared = MainQueue()

    private var tasks: [() -> Void] = []
    private let lock = NSLock()
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        _ = GLib.idleAdd { _ in
            MainQueue.shared.drain()
            return GLib.sourceContinue
        }
    }

    func async(_ block: @escaping () -> Void) {
        lock.lock()
        tasks.append(block)
        lock.unlock()
    }

    private func drain() {
        lock.lock()
        let pending = tasks
        tasks.removeAll()
        lock.unlock()
        for task in pending {
            task()
        }
    }
}
