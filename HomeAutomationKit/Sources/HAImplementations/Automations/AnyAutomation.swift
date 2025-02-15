//
//  AnyAutomation.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 13.02.25.
//

import HAModels

public enum AnyAutomation: Codable, Sendable {
    case createScene(CreateScene)
    case energyLowPrice(EnergyLowPrice)
    #if canImport(WeatherKit)
    case gardenWatering(GardenWatering)
    #endif
    case goodNight(GoodNight)
    case healthCheck(HealthCheck)
    case maintenanceAutomation(MaintenanceAutomation)
    case motionAtNight(MotionAtNight)
    case poolPump(PoolPump)
    case restartSystem(RestartSystem)
    case turn(Turn)
    case turnOnForDuration(TurnOnForDuration)
    case updateScenes(UpdateScenes)
    case windowOpen(WindowOpen)

    public var automation: any Automatable {
        switch self {
        case .createScene(let createScene): return createScene
        case .energyLowPrice(let energyLowPrice): return energyLowPrice
        case .motionAtNight(let motionAtNight): return motionAtNight
        case .turnOnForDuration(let turnOnForDuration): return turnOnForDuration
        #if canImport(WeatherKit)
        case .gardenWatering(let gardenWatering): return gardenWatering
        #endif
        case .goodNight(let goodNight): return goodNight
        case .healthCheck(let healthCheck): return healthCheck
        case .maintenanceAutomation(let maintenanceAutomation): return maintenanceAutomation
        case .poolPump(let poolPump): return poolPump
        case .restartSystem(let restartSystem): return restartSystem
        case .turn(let turn): return turn
        case .updateScenes(let updateScenes): return updateScenes
        case .windowOpen(let windowOpen): return windowOpen
        }
    }

    public var automationTypes: [Automatable.Type] {
        var tmp: [Automatable.Type] = [
            CreateScene.self,
            EnergyLowPrice.self,
            GoodNight.self,
            HealthCheck.self,
            MaintenanceAutomation.self,
            MotionAtNight.self,
            PoolPump.self,
            RestartSystem.self,
            Turn.self,
            TurnOnForDuration.self,
            UpdateScenes.self,
            WindowOpen.self
        ]
        
        #if canImport(WeatherKit)
        tmp.append(GardenWatering.self)
        #endif
        return tmp
    }

    public static func create(from automation: any Automatable) -> AnyAutomation {
        if let createScene = automation as? CreateScene {
            return .createScene(createScene)
        } else if let energyLowPrice = automation as? EnergyLowPrice {
            return .energyLowPrice(energyLowPrice)
        } else if let goodNight = automation as? GoodNight {
            return .goodNight(goodNight)
        } else if let healthCheck = automation as? HealthCheck {
            return .healthCheck(healthCheck)
        } else if let maintenanceAutomation = automation as? MaintenanceAutomation {
            return .maintenanceAutomation(maintenanceAutomation)
        } else if let motionAtNight = automation as? MotionAtNight {
            return .motionAtNight(motionAtNight)
        } else if let poolPump = automation as? PoolPump {
            return .poolPump(poolPump)
        } else if let restartSystem = automation as? RestartSystem {
            return .restartSystem(restartSystem)
        } else if let turn = automation as? Turn {
            return .turn(turn)
        } else if let turnOnForDuration = automation as? TurnOnForDuration {
            return .turnOnForDuration(turnOnForDuration)
        } else if let updateScenes = automation as? UpdateScenes {
            return .updateScenes(updateScenes)
        } else if let windowOpen = automation as? WindowOpen {
            return .windowOpen(windowOpen)
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
