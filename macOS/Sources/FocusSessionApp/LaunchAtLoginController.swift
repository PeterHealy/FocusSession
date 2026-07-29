import Foundation
import ServiceManagement

struct LaunchAtLoginController {
    func setEnabled(_ enabled: Bool) -> Result<Void, Error> {
        let service = SMAppService.mainApp

        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled
                || service.status == .requiresApproval {
                try service.unregister()
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
