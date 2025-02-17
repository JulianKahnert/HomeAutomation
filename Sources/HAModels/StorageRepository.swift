//
//  StorageRepository.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 23.07.24.
//

import Foundation

public protocol StorageRepository: Sendable {
    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem?
    func getPrevious(_ entityId: EntityId) async throws -> EntityStorageItem?

    func add(_ item: EntityStorageItem) async throws
    func deleteEntries(olderThan date: Date) async throws
}
