//
//  OnSceneChangeModifier.swift
//  ControllerFeatures
//
//  Custom view modifier that observes scene phase changes
//  and triggers actions when the scene phase transitions occur
//

import SwiftUI

/// View modifier that observes scene phase changes and executes an action
/// whenever the scene phase changes.
///
/// This modifier provides both the old and new ScenePhase values to the action
/// closure, allowing the caller to decide which transitions are relevant.
struct OnSceneChangeModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let action: (ScenePhase, ScenePhase) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { oldPhase, newPhase in
                action(oldPhase, newPhase)
            }
    }
}

extension View {
    /// Performs an action when the app's scene phase changes.
    ///
    /// This modifier is useful for responding to scene phase transitions,
    /// such as when the app becomes active from inactive or background states.
    /// The action receives both the old and new scene phases to allow fine-grained
    /// control over which transitions trigger specific behavior.
    ///
    /// - Parameter action: The action to perform when scene phase changes.
    ///                     Receives the old and new scene phases as parameters.
    ///
    /// # Example
    /// ```swift
    /// ContentView()
    ///     .onSceneChange { oldPhase, newPhase in
    ///         if newPhase == .active {
    ///             store.send(.scenePhaseChanged(old: oldPhase, new: newPhase))
    ///         }
    ///     }
    /// ```
    func onSceneChange(perform action: @escaping (ScenePhase, ScenePhase) -> Void) -> some View {
        modifier(OnSceneChangeModifier(action: action))
    }
}
