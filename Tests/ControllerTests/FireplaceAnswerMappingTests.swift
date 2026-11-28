//
//  FireplaceAnswerMappingTests.swift
//  ControllerTests
//

import Foundation
import HAModels
@testable import ServerClient
import Testing

struct FireplaceAnswerMappingTests {
    private let since = Date(timeIntervalSince1970: 1_000)

    private func answer(_ value: Components.Schemas.Value) -> Components.Schemas.EntityState {
        .init(entityId: .init(Fireplace.stateId), valueKind: Fireplace.stateId.characteristicType.rawValue, value: value, changed: true, timestamp: since)
    }

    @Test func anOnAnswerIsOnSinceItsTimestamp() {
        let state = FireplaceState(answer(.case1(true)))

        #expect(state.isOn)
        #expect(state.since == since)
    }

    @Test func anOffAnswerIsOff() {
        #expect(FireplaceState(answer(.case1(false))) == .off)
    }

    @Test func anAnswerThatIsNoBooleanIsOff() {
        #expect(FireplaceState(answer(.case3("on"))) == .off)
    }

    @Test func theServerNamesTheQuestionAndTheEnd() {
        let body = Components.Schemas.Fireplace(isOn: true,
                                                since: since,
                                                asksAt: since.addingTimeInterval(60),
                                                isAsking: true,
                                                endsAt: since.addingTimeInterval(120))
        let state = FireplaceState(body)

        #expect(state.asksAt == since.addingTimeInterval(60))
        #expect(state.isAsking)
        #expect(state.endsAt == since.addingTimeInterval(120))
    }

    @Test func aServerWithoutTheQuestionIsNotAsking() {
        #expect(!FireplaceState(Components.Schemas.Fireplace(isOn: true, since: since)).isAsking)
    }

    @Test func theRequestNamesTheEntityWithAnEmptyCharacteristicsName() {
        let id = Components.Schemas.EntityId(Fireplace.stateId)

        #expect(id.characteristicsName == (Fireplace.stateId.characteristicsName ?? ""))
        #expect(id.characteristicType == Fireplace.stateId.characteristicType.rawValue)
    }
}
