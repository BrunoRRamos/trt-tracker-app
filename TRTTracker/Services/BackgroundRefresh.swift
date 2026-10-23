import BackgroundTasks
import Foundation

/// Atualização em segundo plano para manter a janela de lembretes preenchida (RF-NOT-04).
enum BackgroundRefresh {
    static let identifier = "com.trttracker.TRTTracker.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
