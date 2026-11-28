//
//  WindowContentState+Sample.swift
//  FlowKit Controller
//

#if os(iOS)
import Foundation
import HAModels

extension WindowContentState {
    /// Eight open windows opened a minute apart, for previews; the first `overdueCount` are overdue.
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

    /// One overdue window, `overdueBy` past its closing time, for previews of the "+m:ss" label.
    static func overdueSample(overdueBy: TimeInterval, room: String = "Schlafzimmer", name: String = "Fenster links", now: Date = Date()) -> WindowContentState {
        let closeBy = now.addingTimeInterval(-overdueBy)
        let window = Window(id: Window.id(room: room, name: name),
                            name: name,
                            room: room,
                            opened: closeBy.addingTimeInterval(-25 * 60),
                            closeBy: closeBy,
                            isOverdue: true)
        return WindowContentState(sortedWindows: [window], outdoorTemperature: 6)
    }
}
#endif
