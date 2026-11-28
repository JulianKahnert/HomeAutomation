//
//  StateChange.swift
//  HAModels
//

/// What a write sets: the state after the write and whether it changed.
public struct StateChange: Sendable, Equatable {
    public let item: EntityStorageItem
    /// The value of ``item``; a state without one is no state to answer.
    public let value: Value
    public let changed: Bool

    /// - Returns: `nil` when the item carries no value.
    public init?(item: EntityStorageItem, changed: Bool) {
        guard let value = item.value else { return nil }
        self.item = item
        self.value = value
        self.changed = changed
    }
}
