//
//  ContentView.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 26.07.24.
//

import HAImplementations
import HAModels
import Logging
import SwiftUI

struct ContentView: View {
    @Binding var shouldCrashIfActorSystemInitFails: Bool
    @Binding var entities: [EntityStorageItem]
    @State private var showSettings = false
    @AppStorage("ActorSystemServerAddress") private var serverAddress = CustomActorSystem.Address(host: "localhost", port: 8888)

    var body: some View {
        List(entities.reversed(), id: \.self) { (item: EntityStorageItem) in
            VStack(alignment: .leading) {
                HStack {
                    Text(item.timestamp.formatted(date: .numeric, time: .standard))
                        .foregroundColor(.gray)

                    Text(item.entityId.description)
                    ForEach(EntityStorageItemType.allCases, id: \.self) { type in
                        dataView(item, for: type)
                    }
                }
                Text(item.entityId.placeId)
                    .foregroundColor(.gray)
                    .font(.subheadline)
            }
            .listRowBackground((item.stateOfCharge ?? 100) <= 5 ? Color.yellow.opacity(0.2) : nil)
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView(serverAddress: $serverAddress)
        }
        .navigationTitle(serverAddress.description)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $shouldCrashIfActorSystemInitFails, label: {
                    Text("Should wait for ActorSystem?")
                })
            }
            ToolbarItem {
                Button("Preferences", systemImage: "gear") {
                    showSettings.toggle()
                }
            }
        }
        .onChange(of: serverAddress, initial: true) { _, serverAddress in
            serverAddressChanged(to: serverAddress)
        }
    }

    @ViewBuilder
    private func dataView(_ item: EntityStorageItem, for type: EntityStorageItemType) -> some View {
        switch type {
        case .motion:
            if let motionDetected = item.motionDetected {
                Spacer()
                Image(systemName: motionDetected ? "figure.walk.motion" : "figure.stand")
            } else {
                EmptyView()
            }
        case .illuminance:
            if let illuminance = item.illuminance {
                Spacer()
                Label(illuminance.formatted(.measurement(width: .wide, usage: .general, numberFormatStyle: .number.precision(.fractionLength(0)))), systemImage: "light.max")
            } else {
                EmptyView()
            }
        case .isDeviceOn:
            if let isDeviceOn = item.isDeviceOn {
                Spacer()
                Image(systemName: isDeviceOn ? "lightswitch.on" : "lightswitch.off")
            } else {
                EmptyView()
            }
        case .isContactOpen:
            if let isContactOpen = item.isContactOpen {
                Spacer()
                Label(isContactOpen ? "open" : "closed", systemImage: "contact.sensor")
            } else {
                EmptyView()
            }
        case .isDoorLocked:
            if let isDoorLocked = item.isDoorLocked {
                Spacer()
                Label(!isDoorLocked ? "open" : "closed", systemImage: !isDoorLocked ? "lock.open" : "lock")
            } else {
                EmptyView()
            }
        case .stateOfCharge:
            if let stateOfCharge = item.stateOfCharge {
                Spacer()
                HStack {
                    Text("\(stateOfCharge) %")
                    Image(systemName: "battery.25percent")
                }
            } else {
                EmptyView()
            }
        case .isHeaterActive:
            if let isHeaterActive = item.isHeaterActive {
                Spacer()
                HStack {
                    Text("\(isHeaterActive ? "active" : "inactive")")
                    Image(systemName: "windshield.rear.and.heat.waves")
                }
            } else {
                EmptyView()
            }
        }
    }

    private func serverAddressChanged(to address: CustomActorSystem.Address) {
        #warning("TODO: add this again")
//        Task {
//            do {
//                log.info("Connecting to server at \(address)")
//                try await actorSystem.join(host: address.host, port: address.port)
//            } catch {
//                fatalError("Failed to start server connection \(error)")
//            }
//        }
    }

}

#Preview {
    ContentView(shouldCrashIfActorSystemInitFails: .constant(true), entities: .constant([]))
}
