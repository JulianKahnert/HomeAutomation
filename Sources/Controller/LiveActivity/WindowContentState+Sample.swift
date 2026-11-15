//
//  WindowContentState+Sample.swift
//  FlowKit Controller
//

#if os(iOS)
import Foundation
import HAModels

extension WindowContentState {
    /// Eight offene Fenster opened a minute apart, for previews; the first `overdueCount` are überschritten.
    static func sample(overdueCount: Int = 1, outdoorTemperature: Double? = 7.4, now: Date = Date()) -> WindowContentState {
        let rooms = ["Küche", "Bad", "Büro", "Flur", "Schlafzimmer", "Wohnzimmer", "Kinderzimmer", "Keller"]
        let windows = rooms.enumerated().map { index, room in
            let opened = now.addingTimeInterval(Double(-index) * 60)
            return Window(id: Window.id(room: room, name: "Fenster"),
                          name: "Fenster",
                          room: room,
                          opened: opened,
                          closeBy: opened.addingTimeInterval(25 * 60),
                          isOverdue: index < overdueCount)
        }
        return WindowContentState(sortedWindows: windows, outdoorTemperature: outdoorTemperature)
    }
}
#endif
