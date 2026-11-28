//
//  OpenAPIController.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 14.02.25.
//

import Dependencies
import Fluent
import HAApplicationLayer
import HAImplementations
import HAModels
import OpenAPIRuntime
import Vapor

struct OpenAPIController: APIProtocol {
    @Dependency(\.request) var request

    /// Largest page size any list endpoint hands to the database. Mirrors the `maximum: 1000`
    /// declared on the `limit` parameters in `openapi.yaml`.
    static let maxLimit = 1000
    static let defaultLimit = 100

    /// Enforces the `minimum`/`maximum` bounds from `openapi.yaml` server-side.
    ///
    /// swift-openapi-generator parses `limit` but does not validate its declared bounds, so
    /// without this a caller can pass `limit=2000000000` and have Fluent load a whole table
    /// into memory, or `limit=0`/negative values and produce an invalid SQL `LIMIT`.
    static func clampedLimit(_ requested: Int?, default defaultValue: Int = Self.defaultLimit) -> Int {
        min(max(requested ?? defaultValue, 1), maxLimit)
    }

    // MARK: - /config/automations

    func getAutomations(_ input: Operations.GetAutomations.Input) async throws -> Operations.GetAutomations.Output {
        let lastRuns = try await request.application.journalReader.latestRunPerAutomation()
        let automations = try await request.application.configReader.load().automations.map(\.automation)
            .map { tmp in
                Components.Schemas.Automation(name: tmp.name,
                                              isActive: tmp.isActive,
                                              // a run that is recorded and not finished; a restart marks the leftovers interrupted
                                              isRunning: lastRuns[tmp.name]?.outcome == .running,
                                              _type: String(describing: type(of: tmp)),
                                              recordsRuns: tmp.recordsRuns,
                                              lastRun: lastRuns[tmp.name].map(Components.Schemas.AutomationRun.init),
                                              entities: tmp.involvedEntityIds.map(Components.Schemas.EntityId.init))
            }
        return .ok(.init(body: .json(automations)))
    }

    func getAutomationRuns(_ input: Operations.GetAutomationRuns.Input) async throws -> Operations.GetAutomationRuns.Output {
        let runs = try await request.application.journalReader.runs(for: input.path.name,
                                                                              startDate: input.query.startDate,
                                                                              endDate: input.query.endDate,
                                                                              limit: Self.clampedLimit(input.query.limit))
        return .ok(.init(body: .json(runs.map(Components.Schemas.AutomationRun.init))))
    }

    func getRecentRuns(_ input: Operations.GetRecentRuns.Input) async throws -> Operations.GetRecentRuns.Output {
        let runs = try await request.application.journalReader.latestRuns(since: input.query.since,
                                                                                    limit: Self.clampedLimit(input.query.limit))
        return .ok(.init(body: .json(runs.map(Components.Schemas.AutomationRun.init))))
    }

    func activateAutomation(_ input: Operations.ActivateAutomation.Input) async throws -> Operations.ActivateAutomation.Output {
        guard let name = request.parameters.get("name"),
              !name.isEmpty else {
            throw Abort(.notFound, reason: "Automation name not provided")
        }

        try await request.application.commandPort.setAutomationActive(name: name, to: true)
        return .ok
    }

    func deactivateAutomation(_ input: Operations.DeactivateAutomation.Input) async throws -> Operations.DeactivateAutomation.Output {
        guard let name = request.parameters.get("name"),
              !name.isEmpty else {
            throw Abort(.notFound, reason: "Automation name not provided")
        }

        try await request.application.commandPort.setAutomationActive(name: name, to: false)
        return .ok
    }

    func stopAutomation(_ input: Operations.StopAutomation.Input) async throws -> Operations.StopAutomation.Output {
        guard let name = request.parameters.get("name"),
              !name.isEmpty else {
            throw Abort(.notFound, reason: "Automation name not provided")
        }

        try await request.application.commandPort.stopAutomation(name: name)
        return .ok
    }

    // MARK: - /pushdevices

    func registerPushDevice(_ input: Operations.RegisterPushDevice.Input) async throws -> Operations.RegisterPushDevice.Output {
       guard case let .json(token) = input.body else {
            throw Abort(.badRequest, reason: "Invalid JSON body")
        }
        request.logger.info("Adding/updating push device token: \(token.tokenType.rawValue)")

        switch token.tokenType {
        case .pushNotification:
            assert(token.activityType == nil, "For pushNotification, activityType should be nil")

            // upsert: update existing token or create new one
            let existingQuery = DeviceToken
                .query(on: request.db)
                .filter(\.$deviceName == token.deviceName)
                .filter(\.$tokenType == token.tokenType.rawValue)
            if let existing = try await existingQuery.first() {
                existing.tokenString = token.tokenString
                try await existing.save(on: request.db)
                request.logger.info("Updated existing \(token.tokenType.rawValue) token for \(token.deviceName)")
            } else {
                let newPushDevice = DeviceToken(deviceName: token.deviceName,
                                                tokenString: token.tokenString,
                                                tokenType: token.tokenType.rawValue,
                                                activityType: nil)
                try await newPushDevice.save(on: request.db)
                request.logger.info("Created new \(token.tokenType.rawValue) token for \(token.deviceName)")
            }
            return .ok

        case .liveActivityStart:
            // One push-to-start token per device and activity type; an app that names no type registers the window's.
            let activityType = token.activityType ?? WindowContentState.activityTypeName
            let existing = try await DeviceToken
                .query(on: request.db)
                .filter(\.$deviceName == token.deviceName)
                .filter(\.$tokenType == token.tokenType.rawValue)
                .all()
                .first { $0.startActivityType == activityType }
            if let existing {
                existing.tokenString = token.tokenString
                existing.activityType = activityType
                try await existing.save(on: request.db)
                request.logger.info("Updated existing liveActivityStart token for \(token.deviceName) (activity: \(activityType))")
            } else {
                let newPushDevice = DeviceToken(deviceName: token.deviceName,
                                                tokenString: token.tokenString,
                                                tokenType: token.tokenType.rawValue,
                                                activityType: activityType)
                try await newPushDevice.save(on: request.db)
                request.logger.info("Created new liveActivityStart token for \(token.deviceName) (activity: \(activityType))")
            }
            return .ok

        case .liveActivityUpdate:
            guard let activityType = token.activityType else {
                request.logger.error("Token of type liveActivityUpdate must contain activityType")
                return .internalServerError
            }

            // upsert: update existing token or create new one
            let existingQuery = DeviceToken
                .query(on: request.db)
                .filter(\.$deviceName == token.deviceName)
                .filter(\.$tokenType == token.tokenType.rawValue)
                .filter(\.$activityType == activityType)
            if let existing = try await existingQuery.first() {
                existing.tokenString = token.tokenString
                try await existing.save(on: request.db)
                request.logger.info("Updated existing liveActivityUpdate token for \(token.deviceName) (activity: \(activityType))")
            } else {
                let newPushDevice = DeviceToken(deviceName: token.deviceName,
                                                tokenString: token.tokenString,
                                                tokenType: token.tokenType.rawValue,
                                                activityType: activityType)
                try await newPushDevice.save(on: request.db)
                request.logger.info("Created new liveActivityUpdate token for \(token.deviceName) (activity: \(activityType))")
            }
            return .ok
        }
    }

    // MARK: - /windowopenstates
    func getWindowStates(_ input: Operations.GetWindowStates.Input) async throws -> Operations.GetWindowStates.Output {
        let contentState = try await request.application.storageReader.windowContentState()
        let windows = contentState.windows.map { window in
            Components.Schemas.WindowState(id: window.id,
                                           name: window.name,
                                           room: window.room,
                                           openedIsoTimeStamp: window.opened.ISO8601Format(),
                                           closeByIsoTimeStamp: window.closeBy.ISO8601Format(),
                                           isOverdue: window.isOverdue)
        }

        return .ok(.init(body: .json(.init(windowStates: windows,
                                           openCount: contentState.openCount,
                                           overdueCount: contentState.overdueCount,
                                           outdoorTemperature: contentState.outdoorTemperature,
                                           staleDateIsoTimeStamp: contentState.staleDate?.ISO8601Format()))))
    }

    // MARK: - /entities/state

    func setEntityState(_ input: Operations.SetEntityState.Input) async throws -> Operations.SetEntityState.Output {
        guard case .json(let body) = input.body else { throw Abort(.badRequest) }
        guard let type = CharacteristicsType(rawValue: body.entityId.characteristicType) else { return .badRequest }
        let characteristicsName = body.entityId.characteristicsName.flatMap { $0.isEmpty ? nil : $0 }
        let entityId = EntityId(placeId: body.entityId.placeId, name: body.entityId.name,
                                characteristicsName: characteristicsName, characteristic: type)

        // Only a server-owned entity of a kind the descriptor lets the app set; any other one stays unchanged.
        guard entityId.isServerOwned, ValueDescriptor.descriptor(for: type).isSettableFromApp else { return .forbidden }
        let value = Value(body.value)
        let change: StateChange
        do {
            change = try await request.application.commandPort.setState(entityId, value: value)
        } catch ReportError.valueDoesNotFit {
            return .badRequest
        }
        let item = change.item
        return .ok(.init(body: .json(.init(entityId: .init(entityId),
                                           valueKind: type.rawValue,
                                           value: .init(change.value),
                                           changed: change.changed,
                                           origin: item.origin.rawValue,
                                           timestamp: item.timestamp))))
    }

    // MARK: - /entities/history

    func getEntityHistory(_ input: Operations.GetEntityHistory.Input) async throws -> Operations.GetEntityHistory.Output {
        // Extract and validate required query parameters
        guard let characteristicType = CharacteristicsType(rawValue: input.query.characteristicType) else {
            throw Abort(.badRequest, reason: "Invalid characteristic type: \(input.query.characteristicType)")
        }

        let entityId = EntityId(
            placeId: input.query.placeId,
            name: input.query.name,
            characteristicsName: input.query.characteristicsName,
            characteristic: characteristicType
        )

        // Extract optional date parameters (already parsed by OpenAPI)
        let startDate = input.query.startDate
        let endDate = input.query.endDate
        let cursor = input.query.cursor
        let limit = Self.clampedLimit(input.query.limit)

        let historyItems = try await request.application.storageReader.getHistory(
            for: entityId,
            startDate: startDate,
            endDate: endDate,
            cursor: cursor,
            limit: limit,
            includePrevious: input.query.includePrevious ?? false
        )
        var schemaItems = historyItems.map(Components.Schemas.EntityHistoryItem.init)

        // The last report is stored with the entity and belongs to the newest change only.
        if cursor == nil, !schemaItems.isEmpty, let current = try await request.application.storageReader.getCurrent(entityId),
           let lastReport = current.lastReport,
           abs(current.timestamp.timeIntervalSince(schemaItems[0].timestamp)) < 1 {
            schemaItems[0].lastReport = lastReport
        }

        // Calculate next cursor (timestamp of last item, or nil if no more data)
        let nextCursor = schemaItems.last?.timestamp

        let response = Components.Schemas.EntityHistoryResponse(
            items: schemaItems,
            nextCursor: nextCursor
        )

        return .ok(.init(body: .json(response)))
    }

    func getRoomHistory(_ input: Operations.GetRoomHistory.Input) async throws -> Operations.GetRoomHistory.Output {
        let histories = try await request.application.storageReader.getRoomHistory(placeId: input.query.placeId,
                                                                                               startDate: input.query.startDate,
                                                                                               endDate: input.query.endDate,
                                                                                               includePrevious: input.query.includePrevious ?? false)
        let body = histories.map { history in
            Components.Schemas.EntityHistory(entityId: .init(history.entityId),
                                             items: history.items.map(Components.Schemas.EntityHistoryItem.init))
        }
        return .ok(.init(body: .json(body)))
    }

    func getHeatingOverview(_ input: Operations.GetHeatingOverview.Input) async throws -> Operations.GetHeatingOverview.Output {
        let rooms = try await heatingRooms().map(\.heatingSources)
        let overview = try await HeatingOverviewBuilder(detail: heatingDetailBuilder()).overview(for: rooms)
        return .ok(.init(body: .json(.init(overview))))
    }

    func getHeatingRoom(_ input: Operations.GetHeatingRoom.Input) async throws -> Operations.GetHeatingRoom.Output {
        guard let range = HeatingRange(rawValue: input.query.range ?? HeatingRange.day.rawValue) else {
            return .badRequest(.init())
        }
        let placeId = input.path.placeId
        guard let room = try await heatingRooms().first(where: { $0.placeId == placeId }) else {
            return .notFound(.init())
        }
        let detail = try await heatingDetailBuilder().detail(for: room.heatingSources, range: range)
        return .ok(.init(body: .json(.init(detail))))
    }

    /// The heating automations of the deployed configuration.
    private func heatingRooms() async throws -> [RoomHeating] {
        try await request.application.configReader.load().automations.compactMap { $0.automation as? RoomHeating }
    }

    /// Both heating endpoints cut the days by the local clock of the house, Europe/Berlin.
    private func heatingDetailBuilder() -> HeatingRoomDetailBuilder {
        let storage = request.application.storageReader
        return HeatingRoomDetailBuilder(storage: storage,
                                        journal: request.application.journalReader,
                                        lastReport: { try? await storage.getCurrent($0)?.lastReport },
                                        calendar: HeatingOverviewBuilder.berlin)
    }

    // MARK: - /heating/fireplace

    func getFireplace(_ input: Operations.GetFireplace.Input) async throws -> Operations.GetFireplace.Output {
        let state = try await Fireplace.state(from: request.application.storageReader)
        return .ok(.init(body: .json(.init(state))))
    }

    /// The answer to "Ist der Kamin noch an?": "Nein" switches the fireplace off, "Ja" sets the next question
    /// `Fireplace.maxDuration` ahead. Both go through the core with origin `app`; `FireplaceTimeout` hears the change
    /// and ends the question's Live Activity on every device.
    func answerFireplaceQuestion(_ input: Operations.AnswerFireplaceQuestion.Input) async throws -> Operations.AnswerFireplaceQuestion.Output {
        guard case .json(let body) = input.body else { throw Abort(.badRequest) }
        let commandPort = request.application.commandPort
        guard body.stillOn else {
            _ = try await commandPort.setState(Fireplace.stateId, value: .bool(false))
            return .ok(.init(body: .json(.init(FireplaceState.off))))
        }

        // The reads come from the database, which may lag the core by the persist delay; a fireplace switched on
        // a moment ago therefore reads off here and "Ja" has nothing to extend.
        let storage = request.application.storageReader
        let fireplace = try await storage.getCurrent(Fireplace.stateId)
        guard Fireplace.state(of: fireplace).isOn else {
            return .ok(.init(body: .json(.init(FireplaceState.off))))
        }
        let next = Deadline.running(until: Date().addingTimeInterval(Fireplace.maxDuration))
        let change = try await commandPort.setState(Fireplace.questionId, value: .text(next.text))
        return .ok(.init(body: .json(.init(Fireplace.state(of: fireplace, question: change.item)))))
    }
}

extension Components.Schemas.Fireplace {
    init(_ state: FireplaceState) {
        self.init(isOn: state.isOn, since: state.since, asksAt: state.asksAt, isAsking: state.isAsking, endsAt: state.endsAt)
    }
}

extension Components.Schemas.EntityId {
    init(_ entityId: EntityId) {
        self.init(placeId: entityId.placeId,
                  name: entityId.name,
                  characteristicsName: entityId.characteristicsName ?? "",
                  characteristicType: entityId.characteristicType.rawValue)
    }
}

extension Components.Schemas.AutomationRun {
    init(_ run: AutomationRun) {
        self.init(id: run.id.uuidString,
                  automationName: run.automationName,
                  startedAt: run.startedAt,
                  endedAt: run.endedAt,
                  trigger: .init(kind: .init(rawValue: run.trigger.kind.rawValue) ?? .entityChange,
                                 entityId: run.trigger.entityId.map(Components.Schemas.EntityId.init),
                                 summary: run.trigger.summary),
                  outcome: .init(rawValue: run.outcome.rawValue) ?? .failed,
                  errorDescription: run.errorDescription)
    }
}

extension Components.Schemas.EntityHistoryItem {
    init(_ item: EntityStorageItem) {
        self.init(valueKind: item.kind?.rawValue,
                  value: item.value.map { .init($0) },
                  timestamp: item.timestamp,
                  origin: item.origin.rawValue,
                  lastReport: item.lastReport)
    }
}

extension Components.Schemas.Value {
    init(_ value: Value) {
        switch value {
        case .bool(let bool): self = .case1(bool)
        case .number(let number): self = .case2(number)
        case .text(let text): self = .case3(text)
        }
    }
}

extension Value {
    init(_ payload: Components.Schemas.Value) {
        switch payload {
        case .case1(let bool): self = .bool(bool)
        case .case2(let number): self = .number(number)
        case .case3(let text): self = .text(text)
        }
    }
}

extension Components.Schemas.HeatingIstSource {
    init(_ source: HeatingIstSource) {
        switch source {
        case .roomSensor(let name): self.init(kind: .roomSensor, names: [name])
        case .thermostats(let names): self.init(kind: .thermostats, names: names)
        }
    }
}

extension Components.Schemas.HeatingOverview {
    init(_ overview: HeatingOverview) {
        self.init(rooms: overview.rooms.map {
            .init(placeId: $0.placeId, name: $0.name, shortName: $0.shortName, ist: $0.ist, sollPlan: $0.sollPlan, delta: $0.delta, istSource: .init($0.istSource),
                  followsFireplace: $0.followsFireplace)
        }, heatmap: overview.heatmap.map {
            .init(placeId: $0.placeId, day: $0.day, segment: $0.segment, delta: $0.delta)
        })
    }
}

extension Components.Schemas.HeatingRoomDetail {
    init(_ detail: HeatingRoomDetail) {
        let source = Components.Schemas.HeatingIstSource(detail.istSource)
        self.init(placeId: detail.placeId,
                  name: detail.name,
                  range: detail.range.rawValue,
                  istSource: source,
                  radiators: detail.radiators,
                  samples: detail.samples.map { .init(date: $0.date, ist: $0.ist, sollPlan: $0.sollPlan, valves: $0.valves) },
                  lastIst: detail.lastIst,
                  events: detail.events.map { .init(source: $0.source.rawValue, title: $0.title, reason: $0.reason, start: $0.start, end: $0.end, pin: $0.pin) })
    }
}
