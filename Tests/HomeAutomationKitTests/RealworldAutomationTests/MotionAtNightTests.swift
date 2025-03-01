#warning("TODO: add tests")
//import Foundation
//import HAApplicationLayer
//import HAImplementations
//import HAModels
//import Server
//import Testing
//
//@HomeManagerActor
//struct MotionAtNightTests {
//    let noMotionWait: Duration = .milliseconds(200)
//    let dimWait: Duration = .milliseconds(50)
//    let deviceEveMotion = EveMotion(query: .init(placeId: "room1", name: "motion1"))
//    let deviceLightBulb = LightBulbWhite(query: .init(placeId: "room1", name: "lightbulb1"))
//    let deviceWindowContact = WindowContactSensor(query: .init(placeId: "room1", name: "contact1"))
//    let automation: MotionAtNight
//    init() {
//        automation = MotionAtNight("motion-at-night",
//                                   noMotionWait: noMotionWait,
//                                   dimWait: dimWait,
//                                   motionSensors: [deviceEveMotion],
//                                   lightSensor: deviceEveMotion,
//                                   lights: [deviceLightBulb],
//                                   minBrightness: 0.1)
////        config = Config(automations: [automation],
////                        location: .oldenburgLocation,
////                        devices: [deviceEveMotion, deviceLightBulb, deviceWindowContact])
//    }
//
//    @Test("Should not trigger on 'no motion' events")
//    func noTriggerOnNoMotionEvent() async throws {
//        // prepare
//
//        // run
//        let mockHomeAdapter = MockHomeAdapter()
//        mockHomeAdapter.storageItems = [
//            EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
//                              timestamp: Date(),
//                              motionDetected: false,
//                              illuminance: nil,
//                              isDeviceOn: nil,
//                              isContactOpen: nil,
//                              isDoorLocked: nil,
//                              stateOfCharge: nil,
//                              isHeaterActive: nil),
//            EntityStorageItem(entityId: deviceEveMotion.lightSensorId!,
//                              timestamp: Date(),
//                              motionDetected: nil,
//                              illuminance: .init(value: 5, unit: .lux),
//                              isDeviceOn: nil,
//                              isContactOpen: nil,
//                              isDoorLocked: nil,
//                              stateOfCharge: nil,
//                              isHeaterActive: nil),
//            EntityStorageItem(entityId: deviceLightBulb.switchId,
//                              timestamp: Date(),
//                              motionDetected: nil,
//                              illuminance: nil,
//                              isDeviceOn: false,
//                              isContactOpen: nil,
//                              isDoorLocked: nil,
//                              stateOfCharge: nil,
//                              isHeaterActive: nil)
//        ]
//        let mockStorageRepo = MockStorageRepository(items: mockHomeAdapter.storageItems)
//        let runLoopTask = Task.detached {
////            await runLoop(with: mockHomeAdapter,
////                          storageRepo: mockStorageRepo,
////                          config: config)
//            
//            let homeEvents = AsyncStream.makeStream(of: HomeEvent.self)
//            await HomeEventProcessingJob(homeEventsStream: homeEvents.stream,
//                                   automationService: automationService,
//                                         homeManager: mockHomeAdapter).run()
//        }
//
//        // trigger motion
//        mockHomeAdapter.entityStreamContinuation.yield(EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
//                                                                         timestamp: Date(),
//                                                                         motionDetected: false,
//                                                                         illuminance: nil,
//                                                                         isDeviceOn: nil,
//                                                                         isContactOpen: nil,
//                                                                         isDoorLocked: nil,
//                                                                         stateOfCharge: nil,
//                                                                         isHeaterActive: nil))
//
//        try await Task.sleep(for: noMotionWait / 2)
//        runLoopTask.cancel()
//
//        // assert
//        #expect(mockHomeAdapter.getSortedTraceMap() == ["setUsedEntityIds.count:2: 1"])
//    }
//
////    @Test("Test that the automation will only be triggered on motion events")
////    func triggerOnMotionEvent() async throws {
////        // prepare
////
////        // run
////        let mockHomeAdapter = MockHomeAdapter(with: config)
////        mockHomeAdapter.storageItems = [
////            EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                              timestamp: Date(),
////                              motionDetected: false,
////                              illuminance: nil,
////                              isDeviceOn: nil,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceEveMotion.lightSensorId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: .init(value: 5, unit: .lux),
////                              isDeviceOn: nil,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceLightBulb.switchId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: nil,
////                              isDeviceOn: false,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil)
////        ]
////        let mockStorageRepo = MockStorageRepository(items: mockHomeAdapter.storageItems)
////        let runLoopTask = Task.detached(priority: .userInitiated) {
////            await runLoop(with: mockHomeAdapter, storageRepo: mockStorageRepo, config: config)
////        }
////
////        // trigger motion
////        mockHomeAdapter.entityStreamContinuation.yield(EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                                                                         timestamp: Date(),
////                                                                         motionDetected: true,
////                                                                         illuminance: nil,
////                                                                         isDeviceOn: nil,
////                                                                         isContactOpen: nil,
////                                                                         isDoorLocked: nil,
////                                                                         stateOfCharge: nil,
////                                                                         isHeaterActive: nil))
////
////        try await Task.sleep(for: noMotionWait)
////        runLoopTask.cancel()
////
////        // assert
////        #expect(Set(mockHomeAdapter.getSortedTraceMap()) == ["setUsedEntityIds.count:2: 1", "action.setBrightness: 1", "action.setColorTemperature: 1", "action.turnOn: 1"])
////
////    }
////
////    @Test("Test that the automation will only be triggered and turn off after motion events")
////    func triggerAndTurnOffOnMotionEvent() async throws {
////        // prepare
////
////        // run
////        let mockHomeAdapter = MockHomeAdapter(with: config)
////        mockHomeAdapter.storageItems = [
////            EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                              timestamp: Date(),
////                              motionDetected: false,
////                              illuminance: nil,
////                              isDeviceOn: nil,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceEveMotion.lightSensorId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: .init(value: 5, unit: .lux),
////                              isDeviceOn: nil,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceLightBulb.switchId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: nil,
////                              isDeviceOn: false,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil)
////        ]
////        let mockStorageRepo = MockStorageRepository(items: mockHomeAdapter.storageItems)
////        let runLoopTask = Task.detached {
////            await runLoop(with: mockHomeAdapter, storageRepo: mockStorageRepo, config: config)
////        }
////
////        // trigger motion
////        mockHomeAdapter.entityStreamContinuation.yield(EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                                                                         timestamp: Date(),
////                                                                         motionDetected: true,
////                                                                         illuminance: nil,
////                                                                         isDeviceOn: nil,
////                                                                         isContactOpen: nil,
////                                                                         isDoorLocked: nil,
////                                                                         stateOfCharge: nil,
////                                                                         isHeaterActive: nil))
////
////        try await Task.sleep(for: noMotionWait + dimWait + .milliseconds(200))
////        runLoopTask.cancel()
////
////        // assert
////        #expect(mockHomeAdapter.getSortedTraceMap() == ["setUsedEntityIds.count:2: 1", "action.setBrightness: 2", "action.setColorTemperature: 1", "action.turnOff: 1", "action.turnOn: 1"])
////    }
////
////    @Test("Test that the automation will not trigger when light sensor has a value above 30")
////    func noTriggerInLight() async throws {
////        // prepare
////
////        // run
////        let mockHomeAdapter = MockHomeAdapter(with: config)
////        mockHomeAdapter.storageItems = [
////            EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                              timestamp: Date(),
////                              motionDetected: false,
////                              illuminance: nil,
////                              isDeviceOn: nil,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceEveMotion.lightSensorId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: .init(value: 500, unit: .lux),
////                              isDeviceOn: nil,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceLightBulb.switchId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: nil,
////                              isDeviceOn: false,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil)
////        ]
////        let mockStorageRepo = MockStorageRepository(items: mockHomeAdapter.storageItems)
////        let runLoopTask = Task.detached {
////            await runLoop(with: mockHomeAdapter, storageRepo: mockStorageRepo, config: config)
////        }
////
////        // trigger motion
////        mockHomeAdapter.entityStreamContinuation.yield(EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                                                                         timestamp: Date(),
////                                                                         motionDetected: true,
////                                                                         illuminance: nil,
////                                                                         isDeviceOn: nil,
////                                                                         isContactOpen: nil,
////                                                                         isDoorLocked: nil,
////                                                                         stateOfCharge: nil,
////                                                                         isHeaterActive: nil))
////
////        try await Task.sleep(for: noMotionWait + dimWait + .milliseconds(50))
////        runLoopTask.cancel()
////
////        // assert
////        #expect(mockHomeAdapter.getSortedTraceMap() == ["setUsedEntityIds.count:2: 1"])
////    }
////
////    @Test("Test if a second trigger extends light duration")
////    func triggerWithDurationExtension() async throws {
////        // prepare
////
////        // run
////        let mockHomeAdapter = MockHomeAdapter(with: config)
////        mockHomeAdapter.storageItems = [
////            EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                              timestamp: Date(),
////                              motionDetected: false,
////                              illuminance: nil,
////                              isDeviceOn: nil,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceEveMotion.lightSensorId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: .init(value: 5, unit: .lux),
////                              isDeviceOn: nil,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceLightBulb.switchId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: nil,
////                              isDeviceOn: false,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil)
////        ]
////        let mockStorageRepo = MockStorageRepository(items: mockHomeAdapter.storageItems)
////        let runLoopTask = Task.detached {
////            await runLoop(with: mockHomeAdapter, storageRepo: mockStorageRepo, config: config)
////        }
////
////        // trigger motion
////        mockHomeAdapter.entityStreamContinuation.yield(EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                                                                         timestamp: Date(),
////                                                                         motionDetected: true,
////                                                                         illuminance: nil,
////                                                                         isDeviceOn: nil,
////                                                                         isContactOpen: nil,
////                                                                         isDoorLocked: nil,
////                                                                         stateOfCharge: nil,
////                                                                         isHeaterActive: nil))
////        try await Task.sleep(for: noMotionWait - .milliseconds(30))
////        mockHomeAdapter.entityStreamContinuation.yield(EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                                                                         timestamp: Date(),
////                                                                         motionDetected: true,
////                                                                         illuminance: nil,
////                                                                         isDeviceOn: nil,
////                                                                         isContactOpen: nil,
////                                                                         isDoorLocked: nil,
////                                                                         stateOfCharge: nil,
////                                                                         isHeaterActive: nil))
////
////        try await Task.sleep(for: noMotionWait + dimWait)
////        runLoopTask.cancel()
////
////        // assert
////        #expect(mockHomeAdapter.getSortedTraceMap() == ["setUsedEntityIds.count:2: 1", "action.setBrightness: 3", "action.setColorTemperature: 2", "action.turnOn: 2"])
////    }
////
////    @Test("Test if the light turns off when the light comes back on", .tags(.localOnly))
////    func lightAfterInitialTrigger() async throws {
////        // prepare
////
////        // run
////        let mockHomeAdapter = MockHomeAdapter(with: config)
////        mockHomeAdapter.storageItems = [
////            EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                              timestamp: Date(),
////                              motionDetected: false,
////                              illuminance: nil,
////                              isDeviceOn: nil,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceEveMotion.lightSensorId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: .init(value: 5, unit: .lux),
////                              isDeviceOn: nil,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceLightBulb.switchId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: nil,
////                              isDeviceOn: false,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil)
////        ]
////        let mockStorageRepo = MockStorageRepository(items: mockHomeAdapter.storageItems)
////        let runLoopTask = Task.detached {
////            await runLoop(with: mockHomeAdapter, storageRepo: mockStorageRepo, config: config)
////        }
////
////        // trigger motion
////        mockHomeAdapter.entityStreamContinuation.yield(EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                                                                         timestamp: Date(),
////                                                                         motionDetected: true,
////                                                                         illuminance: nil,
////                                                                         isDeviceOn: nil,
////                                                                         isContactOpen: nil,
////                                                                         isDoorLocked: nil,
////                                                                         stateOfCharge: nil,
////                                                                         isHeaterActive: nil))
////        try await Task.sleep(for: noMotionWait / 2)
////        mockHomeAdapter.entityStreamContinuation.yield(EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                                                                         timestamp: Date(),
////                                                                         motionDetected: nil,
////                                                                         illuminance: .init(value: 500, unit: .lux),
////                                                                         isDeviceOn: nil,
////                                                                         isContactOpen: nil,
////                                                                         isDoorLocked: nil,
////                                                                         stateOfCharge: nil,
////                                                                         isHeaterActive: nil))
////
////        try await Task.sleep(for: noMotionWait + dimWait + .milliseconds(75))
////        runLoopTask.cancel()
////
////        // assert
////        #expect(mockHomeAdapter.getSortedTraceMap() == ["setUsedEntityIds.count:2: 1", "action.setBrightness: 2", "action.setColorTemperature: 1", "action.turnOff: 1", "action.turnOn: 1"])
////    }
////
////    @Test("Test that the automation will not change lights, when a window is open")
////    func noTriggerWhenWindowContactIsOpen() async throws {
////        // prepare
////        let noMotionWait: Duration = .milliseconds(300)
////        let automation = MotionAtNight(noMotionWait: noMotionWait,
////                                       motionSensors: [deviceEveMotion],
////                                       lightSensor: deviceEveMotion,
////                                       lights: [deviceLightBulb],
////                                       windowContacts: [deviceWindowContact],
////                                       minBrightness: 0.1)
////        let config = Config(automations: [automation],
////                            location: .oldenburgLocation,
////                            devices: [deviceEveMotion, deviceLightBulb, deviceWindowContact])
////
////        // run
////        let mockHomeAdapter = MockHomeAdapter(with: config)
////        mockHomeAdapter.storageItems = [
////            EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                              timestamp: Date(),
////                              motionDetected: false,
////                              illuminance: nil,
////                              isDeviceOn: nil,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceEveMotion.lightSensorId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: .init(value: 5, unit: .lux),
////                              isDeviceOn: nil,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceLightBulb.switchId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: nil,
////                              isDeviceOn: false,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceWindowContact.contactSensorId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: nil,
////                              isDeviceOn: nil,
////                              isContactOpen: true,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil)
////        ]
////        let mockStorageRepo = MockStorageRepository(items: mockHomeAdapter.storageItems)
////        let runLoopTask = Task.detached {
////            await runLoop(with: mockHomeAdapter, storageRepo: mockStorageRepo, config: config)
////        }
////
////        // trigger motion
////        mockHomeAdapter.entityStreamContinuation.yield(EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                                                                         timestamp: Date(),
////                                                                         motionDetected: true,
////                                                                         illuminance: nil,
////                                                                         isDeviceOn: nil,
////                                                                         isContactOpen: nil,
////                                                                         isDoorLocked: nil,
////                                                                         stateOfCharge: nil,
////                                                                         isHeaterActive: nil))
////
////        try await Task.sleep(for: noMotionWait / 2)
////        runLoopTask.cancel()
////
////        // assert
////        #expect(mockHomeAdapter.getSortedTraceMap() == ["setUsedEntityIds.count:3: 1"])
////    }
////
////    @Test("Test that the automation will only be triggered on motion events with closed window")
////    func triggerOnMotionEventWithClosedWindow() async throws {
////        // prepare
////        let noMotionWait: Duration = .milliseconds(300)
////        let automation = MotionAtNight(noMotionWait: noMotionWait,
////                                       motionSensors: [deviceEveMotion],
////                                       lightSensor: deviceEveMotion,
////                                       lights: [deviceLightBulb],
////                                       windowContacts: [deviceWindowContact],
////                                       minBrightness: 0.1)
////        let config = Config(automations: [automation],
////                            location: .oldenburgLocation,
////                            devices: [deviceEveMotion, deviceLightBulb, deviceWindowContact])
////
////        // run
////        let mockHomeAdapter = MockHomeAdapter(with: config)
////        mockHomeAdapter.storageItems = [
////            EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                              timestamp: Date(),
////                              motionDetected: false,
////                              illuminance: nil,
////                              isDeviceOn: nil,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceEveMotion.lightSensorId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: .init(value: 5, unit: .lux),
////                              isDeviceOn: nil,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceLightBulb.switchId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: nil,
////                              isDeviceOn: false,
////                              isContactOpen: nil,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil),
////            EntityStorageItem(entityId: deviceWindowContact.contactSensorId,
////                              timestamp: Date(),
////                              motionDetected: nil,
////                              illuminance: nil,
////                              isDeviceOn: nil,
////                              isContactOpen: true,
////                              isDoorLocked: nil,
////                              stateOfCharge: nil,
////                              isHeaterActive: nil)
////        ]
////        let mockStorageRepo = MockStorageRepository(items: mockHomeAdapter.storageItems)
////        let runLoopTask = Task.detached {
////            await runLoop(with: mockHomeAdapter, storageRepo: mockStorageRepo, config: config)
////        }
////
////        // trigger motion
////        mockHomeAdapter.entityStreamContinuation.yield(EntityStorageItem(entityId: deviceEveMotion.motionSensorId,
////                                                                         timestamp: Date(),
////                                                                         motionDetected: true,
////                                                                         illuminance: nil,
////                                                                         isDeviceOn: nil,
////                                                                         isContactOpen: nil,
////                                                                         isDoorLocked: nil,
////                                                                         stateOfCharge: nil,
////                                                                         isHeaterActive: nil))
////
////        try await Task.sleep(for: .milliseconds(50))
////        runLoopTask.cancel()
////
////        // assert
////        #expect(mockHomeAdapter.getSortedTraceMap() == ["setUsedEntityIds.count:3: 1"])
////    }
//}
