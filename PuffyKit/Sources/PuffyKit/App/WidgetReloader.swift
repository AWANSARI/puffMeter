import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum WidgetReloader {
    static func reload() {
        #if canImport(WidgetKit) && os(iOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
