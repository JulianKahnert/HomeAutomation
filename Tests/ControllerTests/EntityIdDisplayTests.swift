//
//  EntityIdDisplayTests.swift
//  ControllerTests
//

@testable import Controller
import HAModels
import Testing

@Suite("EntityId display")
struct EntityIdDisplayTests {
    @Test("name and kind carry the room, like EntityId.description")
    func nameAndKindCarryTheRoom() {
        let motion = EntityId(placeId: "Arbeitszimmer", name: "Eve Motion", characteristicsName: nil, characteristic: .motionSensor)

        #expect(motion.displayName == "Eve Motion (Arbeitszimmer)")
        #expect(motion.kindInRoom == "Motion Sensor (Arbeitszimmer)")
    }
}
