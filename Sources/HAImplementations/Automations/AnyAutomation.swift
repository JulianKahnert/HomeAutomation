//
//  AnyAutomation.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 13.02.25.
//

import HAModels

public enum AnyAutomation: Codable, Sendable {
    case createScene(CreateScene)
    case databaseCleanup(DatabaseCleanup)
    case energyLowPrice(EnergyLowPrice)
    case fireplaceReminder(FireplaceReminder)
    case fireplaceTimeout(FireplaceTimeout)
    #if canImport(WeatherKit)
    case gardenWatering(GardenWatering)
    #endif
    case healthCheck(HealthCheck)
    case maintenanceAutomation(MaintenanceAutomation)
    case motionAtNight(MotionAtNight)
    case restartSystem(RestartSystem)
    case roomHeating(RoomHeating)
    case setLightProperties(SetLightProperties)
    case turn(Turn)
    case turnOnForDuration(TurnOnForDuration)
    case windowOpen(WindowOpen)
    case upsertScene(UpsertScene)
    case triggerScene(TriggerScene)

    public var automation: any Automatable {
        switch self {
        case .createScene(let createScene): return createScene
        case .databaseCleanup(let databaseCleanup): return databaseCleanup
        case .energyLowPrice(let energyLowPrice): return energyLowPrice
        case .fireplaceReminder(let fireplaceReminder): return fireplaceReminder
        case .fireplaceTimeout(let fireplaceTimeout): return fireplaceTimeout
        case .motionAtNight(let motionAtNight): return motionAtNight
        case .turnOnForDuration(let turnOnForDuration): return turnOnForDuration
        #if canImport(WeatherKit)
        case .gardenWatering(let gardenWatering): return gardenWatering
        #endif
        case .healthCheck(let healthCheck): return healthCheck
        case .maintenanceAutomation(let maintenanceAutomation): return maintenanceAutomation
        case .restartSystem(let restartSystem): return restartSystem
        case .roomHeating(let roomHeating): return roomHeating
        case .setLightProperties(let setLightProperties): return setLightProperties
        case .turn(let turn): return turn
        case .windowOpen(let windowOpen): return windowOpen
        case .upsertScene(let upsertScene): return upsertScene
        case .triggerScene(let triggerScene): return triggerScene
        }
    }

    public var automationTypes: [Automatable.Type] {
        var tmp: [Automatable.Type] = [
            CreateScene.self,
            DatabaseCleanup.self,
            EnergyLowPrice.self,
            FireplaceReminder.self,
            FireplaceTimeout.self,
            HealthCheck.self,
            MaintenanceAutomation.self,
            MotionAtNight.self,
            RestartSystem.self,
            RoomHeating.self,
            SetLightProperties.self,
            Turn.self,
            TurnOnForDuration.self,
            WindowOpen.self,
            UpsertScene.self,
            TriggerScene.self
        ]

        #if canImport(WeatherKit)
        tmp.append(GardenWatering.self)
        #endif
        return tmp
    }

    public static func create(from automation: any Automatable) -> AnyAutomation {
        if let createScene = automation as? CreateScene {
            return .createScene(createScene)
        } else if let databaseCleanup = automation as? DatabaseCleanup {
            return .databaseCleanup(databaseCleanup)
        } else if let energyLowPrice = automation as? EnergyLowPrice {
            return .energyLowPrice(energyLowPrice)
        } else if let fireplaceReminder = automation as? FireplaceReminder {
            return .fireplaceReminder(fireplaceReminder)
        } else if let fireplaceTimeout = automation as? FireplaceTimeout {
            return .fireplaceTimeout(fireplaceTimeout)
        } else if let healthCheck = automation as? HealthCheck {
            return .healthCheck(healthCheck)
        } else if let maintenanceAutomation = automation as? MaintenanceAutomation {
            return .maintenanceAutomation(maintenanceAutomation)
        } else if let motionAtNight = automation as? MotionAtNight {
            return .motionAtNight(motionAtNight)
        } else if let restartSystem = automation as? RestartSystem {
            return .restartSystem(restartSystem)
        } else if let roomHeating = automation as? RoomHeating {
            return .roomHeating(roomHeating)
        } else if let setLightProperties = automation as? SetLightProperties {
            return .setLightProperties(setLightProperties)
        } else if let turn = automation as? Turn {
            return .turn(turn)
        } else if let turnOnForDuration = automation as? TurnOnForDuration {
            return .turnOnForDuration(turnOnForDuration)
        } else if let windowOpen = automation as? WindowOpen {
            return .windowOpen(windowOpen)
        } else if let upsertScene = automation as? UpsertScene {
            return .upsertScene(upsertScene)
        } else if let triggerScene = automation as? TriggerScene {
            return .triggerScene(triggerScene)
        } else {
            #if canImport(WeatherKit)
            if let gardenWatering = automation as? GardenWatering {
                return .gardenWatering(gardenWatering)
            }
            #endif
            fatalError(#function + ": Unsupported automation type \(type(of: automation))")
        }
    }
}
