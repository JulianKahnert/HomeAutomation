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
        let automationNames = await request.application.automationService.getActiveAutomationNames()
        let lastRuns = try await request.application.journalRepository.latestRunPerAutomation()
        let automations = await request.application.automationService.automations
            .map { tmp in
                Components.Schemas.Automation(name: tmp.name,
                                              isActive: tmp.isActive,
                                              isRunning: automationNames.contains(tmp.name),
                                              _type: String(describing: type(of: tmp)),
                                              recordsRuns: tmp.recordsRuns,
                                              lastRun: lastRuns[tmp.name].map(Components.Schemas.AutomationRun.init),
                                              entities: tmp.involvedEntityIds.map(Components.Schemas.EntityId.init))
            }
        return .ok(.init(body: .json(automations)))
    }

    func getAutomationRuns(_ input: Operations.GetAutomationRuns.Input) async throws -> Operations.GetAutomationRuns.Output {
        let runs = try await request.application.journalRepository.runs(for: input.path.name,
                                                                              startDate: input.query.startDate,
                                                                              endDate: input.query.endDate,
                                                                              limit: Self.clampedLimit(input.query.limit))
        return .ok(.init(body: .json(runs.map(Components.Schemas.AutomationRun.init))))
    }

    func getRecentRuns(_ input: Operations.GetRecentRuns.Input) async throws -> Operations.GetRecentRuns.Output {
        let runs = try await request.application.journalRepository.latestRuns(since: input.query.since,
                                                                                    limit: Self.clampedLimit(input.query.limit))
        return .ok(.init(body: .json(runs.map(Components.Schemas.AutomationRun.init))))
    }

    func activateAutomation(_ input: Operations.ActivateAutomation.Input) async throws -> Operations.ActivateAutomation.Output {
        guard let name = request.parameters.get("name"),
              !name.isEmpty else {
            throw Abort(.notFound, reason: "Automation name not provided")
        }

        try await request.application.automationService.setAutomationActive(with: name, to: true)
        return .ok
    }

    func deactivateAutomation(_ input: Operations.DeactivateAutomation.Input) async throws -> Operations.DeactivateAutomation.Output {
        guard let name = request.parameters.get("name"),
              !name.isEmpty else {
            throw Abort(.notFound, reason: "Automation name not provided")
        }

        try await request.application.automationService.setAutomationActive(with: name, to: false)
        return .ok
    }

    func stopAutomation(_ input: Operations.StopAutomation.Input) async throws -> Operations.StopAutomation.Output {
        guard let name = request.parameters.get("name"),
              !name.isEmpty else {
            throw Abort(.notFound, reason: "Automation name not provided")
        }

        await request.application.automationService.stopAutomation(with: name)
        return .ok
    }

    // MARK: - /pushdevices

    func registerPushDevice(_ input: Operations.RegisterPushDevice.Input) async throws -> Operations.RegisterPushDevice.Output {
       guard case let .json(token) = input.body else {
            throw Abort(.badRequest, reason: "Invalid JSON body")
        }
        request.logger.info("Adding/updating push device token: \(token.tokenType.rawValue)")

        switch token.tokenType {
        case .pushNotification, .liveActivityStart:
            assert(token.activityType == nil, "For pushNotification and liveActivityStart, activityType should be nil")

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
                                                activityType: token.activityType)
                try await newPushDevice.save(on: request.db)
                request.logger.info("Created new \(token.tokenType.rawValue) token for \(token.deviceName)")
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
        let contentState = await request.application.homeManager.getWindowContentState()
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
        let homeManager = request.application.homeManager
        let changed: Bool
        do {
            changed = try await homeManager.report(entityId, value: value, origin: .app)
        } catch ReportError.valueDoesNotFit {
            return .badRequest
        }
        // The report just set it: a state that cannot be read back is a failure of the server, not of the request.
        let item: EntityStorageItem
        do {
            item = try await homeManager.getCurrentEntity(with: entityId)
        } catch {
            request.logger.error("Failed to read the state that was just set", metadata: ["entityId": "\(entityId)", "error": "\(error)"])
            throw Abort(.internalServerError)
        }
        guard let state = item.value else {
            request.logger.error("The state that was just set has no value", metadata: ["entityId": "\(entityId)"])
            throw Abort(.internalServerError)
        }
        return .ok(.init(body: .json(.init(entityId: .init(entityId),
                                           valueKind: type.rawValue,
                                           value: .init(state),
                                           changed: changed,
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

        let historyItems = try await request.application.entityStorageDbRepository.getHistory(
            for: entityId,
            startDate: startDate,
            endDate: endDate,
            cursor: cursor,
            limit: limit,
            includePrevious: input.query.includePrevious ?? false
        )
        var schemaItems = historyItems.map(Components.Schemas.EntityHistoryItem.init)

        // The last report lives in memory next to the current state: it belongs to the newest change only.
        if cursor == nil, !schemaItems.isEmpty, let current = await currentState(of: entityId),
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

    /// The current state the server holds; `nil` for an entity it never held. Any other failure is logged.
    private func currentState(of entityId: EntityId) async -> EntityStorageItem? {
        do {
            return try await request.application.homeManager.getCurrentEntity(with: entityId)
        } catch OptionalError.notFound {
            return nil
        } catch {
            request.logger.error("Failed to read the current state", metadata: ["entityId": "\(entityId)", "error": "\(error)"])
            return nil
        }
    }

    func getRoomHistory(_ input: Operations.GetRoomHistory.Input) async throws -> Operations.GetRoomHistory.Output {
        let histories = try await request.application.entityStorageDbRepository.getRoomHistory(placeId: input.query.placeId,
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
        let rooms = await heatingRooms().map(\.heatingSources)
        let overview = try await HeatingOverviewBuilder(detail: heatingDetailBuilder()).overview(for: rooms)
        return .ok(.init(body: .json(.init(overview))))
    }

    func getHeatingRoom(_ input: Operations.GetHeatingRoom.Input) async throws -> Operations.GetHeatingRoom.Output {
        guard let range = HeatingRange(rawValue: input.query.range ?? HeatingRange.day.rawValue) else {
            return .badRequest(.init())
        }
        let placeId = input.path.placeId
        guard let room = await heatingRooms().first(where: { $0.placeId == placeId }) else {
            return .notFound(.init())
        }
        let detail = try await heatingDetailBuilder().detail(for: room.heatingSources, range: range)
        return .ok(.init(body: .json(.init(detail))))
    }

    /// The heating automations of the deployed configuration.
    private func heatingRooms() async -> [RoomHeating] {
        await request.application.automationService.automations.compactMap { $0 as? RoomHeating }
    }

    /// Both heating endpoints cut the days by the local clock of the house, Europe/Berlin.
    private func heatingDetailBuilder() -> HeatingRoomDetailBuilder {
        let homeManager = request.application.homeManager
        return HeatingRoomDetailBuilder(storage: request.application.entityStorageDbRepository,
                                        journal: request.application.journalRepository,
                                        lastReport: { await homeManager.lastReport(of: $0) },
                                        calendar: HeatingOverviewBuilder.berlin)
    }

    // MARK: - /heating/fireplace

    func getFireplace(_ input: Operations.GetFireplace.Input) async throws -> Operations.GetFireplace.Output {
        let state = try await Fireplace.state(with: request.application.homeManager)
        return .ok(.init(body: .json(.init(state))))
    }
}

extension Components.Schemas.Fireplace {
    init(_ state: FireplaceState) {
        self.init(isOn: state.isOn, since: state.since, endsAt: state.endsAt)
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
