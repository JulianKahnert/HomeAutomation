//
//  EntityAdapterable.swift
//  
//
//  Created by Julian Kahnert on 03.07.24.
//

import Distributed

public protocol EntityAdapterable: DistributedActor {
    distributed func getAllEntitiesLive() async -> [EntityStorageItem]

    distributed func perform(_ action: HomeManagableAction) async throws
    distributed func trigger(scene sceneName: String) async throws

    /// The thermostats whose valve position and offset can be read.
    distributed func listThermostats() async throws -> [Thermostat]
    /// Reads one thermostat's valve position and offset; fails when it does not answer within 30 seconds.
    distributed func readThermostat(_ thermostat: Thermostat) async throws -> [EntityStorageItem]
}
