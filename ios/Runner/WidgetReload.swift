import WidgetKit

/// Kept in its own file so the WidgetKit import stays out of AppDelegate.
func reloadWidgets() {
  WidgetCenter.shared.reloadAllTimelines()
}
