//
//  EntitiesListView.swift
//
//
//  Created by Julian Kahnert on 14.11.25.
//

#if canImport(SwiftUI)
import HAModels
import SwiftUI

struct EntitiesListView: View {
    @Binding var shouldCrashIfActorSystemInitFails: Bool
    @Binding var entities: [EntityStorageItem]
    @Binding var showSettings: Bool

    var body: some View {
        List(entities.reversed(), id: \.self) { (item: EntityStorageItem) in
            VStack(alignment: .leading) {
                HStack {
                    Text(item.timestamp.formatted(date: .numeric, time: .standard))
                        .foregroundColor(.gray)

                    Text(item.entityId.description)
                    ForEach(CharacteristicsType.allCases, id: \.self) { type in
                        EntityCharacteristicView(item: item, type: type)
                    }
                }
                Text(item.entityId.placeId)
                    .foregroundColor(.gray)
                    .font(.subheadline)
            }
            .listRowBackground((item.stateOfCharge ?? 100) <= 5 ? Color.yellow.opacity(0.2) : nil)
        }
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
    }
}

#Preview {
    EntitiesListView(
        shouldCrashIfActorSystemInitFails: .constant(true),
        entities: .constant([]),
        showSettings: .constant(false)
    )
}
#endif
