//
//  EntityCharacteristicView.swift
//
//
//  Created by Julian Kahnert on 26.12.24.
//

#if canImport(SwiftUI)
import HAModels
import SwiftUI

struct EntityCharacteristicView: View {
    let item: EntityStorageItem
    let type: CharacteristicsType

    var body: some View {
        switch type {
        case .motionSensor:
            if let motionDetected = item.motionDetected {
                Spacer()
                Image(systemName: motionDetected ? "figure.walk.motion" : "figure.stand")
            }
        case .lightSensor:
            if let illuminance = item.illuminance {
                Spacer()
                Label(illuminance.formatted(.measurement(width: .wide, usage: .general, numberFormatStyle: .number.precision(.fractionLength(0)))), systemImage: "light.max")
            }
        case .switcher:
            if let isDeviceOn = item.isDeviceOn {
                Spacer()
                Image(systemName: isDeviceOn ? "lightswitch.on" : "lightswitch.off")
            }
        case .contactSensor:
            if let isContactOpen = item.isContactOpen {
                Spacer()
                Label(isContactOpen ? "open" : "closed", systemImage: "contact.sensor")
            }
        case .lock:
            if let isDoorLocked = item.isDoorLocked {
                Spacer()
                Label(!isDoorLocked ? "open" : "closed", systemImage: !isDoorLocked ? "lock.open" : "lock")
            }
        case .batterySensor:
            if let stateOfCharge = item.stateOfCharge {
                Spacer()
                HStack {
                    Text("\(stateOfCharge) %")
                    Image(systemName: "battery.25percent")
                }
            }
        case .heating:
            if let isHeaterActive = item.isHeaterActive {
                Spacer()
                HStack {
                    Text("\(isHeaterActive ? "active" : "inactive")")
                    Image(systemName: "windshield.rear.and.heat.waves")
                }
            }
        case .temperatureSensor:
            if let temperature = item.temperatureInC {
                Spacer()
                Label(temperature.formatted(.measurement(width: .abbreviated, usage: .general, numberFormatStyle: .number.precision(.fractionLength(1)))), systemImage: "thermometer.medium")
            }
        case .relativeHumiditySensor:
            if let humidity = item.relativeHumidity {
                Spacer()
                Label("\(Int(humidity)) %", systemImage: "humidity")
            }
        case .carbonDioxideSensorId:
            if let co2 = item.carbonDioxideSensorId {
                Spacer()
                Label("\(co2) ppm", systemImage: "cloud")
            }
        case .pmDensitySensor:
            if let pm = item.pmDensity {
                Spacer()
                Label(String(format: "%.1f µg/m³", pm), systemImage: "aqi.medium")
            }
        case .airQualitySensor:
            if let airQuality = item.airQuality {
                Spacer()
                Label("AQI \(airQuality)", systemImage: "aqi.medium")
            }
        case .brightness:
            if let brightness = item.brightness {
                Spacer()
                Label("\(brightness)%", systemImage: "light.min")
            }
        case .colorTemperature:
            if let colorTemp = item.colorTemperature {
                Spacer()
                // Display as percentage: 0% = warm, 100% = cold
                Label("\(Int(colorTemp * 100))%", systemImage: "light.ribbon")
            }
        case .color:
            if let color = item.color {
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255))
                        .frame(width: 20, height: 20)
                    Text("RGB")
                        .font(.caption)
                }
            }
        case .valve:
            if let valveOpen = item.valveOpen {
                Spacer()
                Label(valveOpen ? "open" : "closed", systemImage: valveOpen ? "spigot" : "spigot.fill")
            }
        }
    }
}

// #Preview {
//    HStack {
//        EntityCharacteristicView(
//            item: EntityStorageItem(
//                entityId: EntityId(placeId: "living-room", type: "light"),
//                brightness: 75,
//                isDeviceOn: true
//            ),
//            type: .brightness
//        )
//    }
// }
#endif
