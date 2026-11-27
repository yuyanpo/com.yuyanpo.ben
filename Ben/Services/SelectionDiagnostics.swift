import Foundation
#if DEBUG
import OSLog
#endif

enum SelectionDiagnostics {
    #if DEBUG
    private static let enabled = CommandLine.arguments.contains("--trace-selection")
    private static let logger = Logger(subsystem: "com.yuyanpo.ben", category: "Selection")
    #endif

    static func record(_ stage: StaticString) {
        #if DEBUG
        if enabled { logger.notice("\(stage.description, privacy: .public)") }
        #endif
    }
}
