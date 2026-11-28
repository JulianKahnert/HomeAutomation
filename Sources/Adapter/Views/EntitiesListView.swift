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
    let entities: [EntityStorageItem]
    @Binding var showSettings: Bool

    var body: some View {
        List(entities.reversed(), id: \.self) { (item: EntityStorageItem) in
            VStack(alignment: .leading) {
                HStack {
                    Text(item.timestamp.formatted(date: .numeric, time: .standard))
                        .foregroundColor(.gray)

                    Text(item.entityId.description)
                    EntityCharacteristicView(item: item)
                }
                Text(item.entityId.placeId)
                    .foregroundColor(.gray)
                    .font(.subheadline)
            }
            .listRowBackground((item.stateOfCharge ?? 100) <= 5 ? Color.yellow.opacity(0.2) : nil)
        }
        .toolbar {
            ToolbarItem {
                Button(String(localized: "Preferences", bundle: .module), systemImage: "gear") {
                    showSettings.toggle()
                }
            }
        }
    }
}

#Preview {
    EntitiesListView(
        entities: [],
        showSettings: .constant(false)
    )
}
#endif
