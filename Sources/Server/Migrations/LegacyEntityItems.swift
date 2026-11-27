//
//  LegacyEntityItems.swift
//  HomeAutomationServer
//

/// The old wide `entityItems` table with one column per value kind. Its model is gone; migrations 01 to 13
/// still create and change it by name, and `DropEntityItems` removes it.
enum LegacyEntityItems {
    static let schema = "entityItems"
}
