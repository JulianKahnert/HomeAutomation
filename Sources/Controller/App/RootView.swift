//
//  RootView.swift
//  
//
//  Created by Julian Kahnert on 16.11.25.
//

import SwiftUI

public struct RootView: View {

    public init() {}

    public var body: some View {
        AppView(store: AppDelegate.store)
    }
}
