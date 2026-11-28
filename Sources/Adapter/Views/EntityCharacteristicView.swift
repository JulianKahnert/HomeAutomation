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

    var body: some View {
        switch item.entityId.characteristicType {
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
                Label(isContactOpen ? String(localized: "open", bundle: .module) : String(localized: "closed", bundle: .module), systemImage: "contact.sensor")
            }
        case .lock:
            if let isDoorLocked = item.isDoorLocked {
                Spacer()
                Label(!isDoorLocked ? String(localized: "open", bundle: .module) : String(localized: "closed", bundle: .module), systemImage: !isDoorLocked ? "lock.open" : "lock")
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
                    Text(isHeaterActive ? String(localized: "active", bundle: .module) : String(localized: "inactive", bundle: .module))
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
            if let density = item.pmDensity {
                Spacer()
                Label(String(format: "%.1f µg/m³", density), systemImage: "aqi.medium")
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
                        .fill(Color(red: Double(color.red), green: Double(color.green), blue: Double(color.blue)))
                        .frame(width: 20, height: 20)
                    Text("RGB")
                        .font(.caption)
                }
            }
        case .targetTemperature:
            if let target = item.targetTemperatureInC {
                Spacer()
                Label(String(format: "%.1f °C", target), systemImage: "target")
            }
        case .heatingMode:
            if let mode = item.heatingMode {
                Spacer()
                Label(String(localized: "mode \(mode.localizedName)", bundle: .module), systemImage: "thermostat")
            }
        case .valvePosition:
            if let percent = item.valvePositionPercent {
                Spacer()
                Label("\(percent) %", systemImage: "spigot")
            }
        case .temperatureCalibration:
            if let offset = item.temperatureCalibrationInC {
                Spacer()
                Label(String(format: "%+.1f °C", offset), systemImage: "plusminus")
            }
        case .energyPrice:
            if let price = item.energyPriceInEURPerKWh {
                Spacer()
                Label(String(format: "%.3f €/kWh", price), systemImage: "bolt")
            }
        case .deadline:
            if let deadline = item.deadline {
                Spacer()
                Label(deadline.localizedDisplayText(), systemImage: "timer")
            }
        case .valve:
            if let valveOpen = item.valveOpen {
                Spacer()
                Label(valveOpen ? String(localized: "open", bundle: .module) : String(localized: "closed", bundle: .module), systemImage: valveOpen ? "spigot" : "spigot.fill")
            }
        }
    }
}

#Preview {
    List {
        HStack {
            Text("Target")
            EntityCharacteristicView(
                item: EntityStorageItem(entityId: EntityId(placeId: "Bad", name: "Thermostat", characteristicsName: nil, characteristic: .targetTemperature),
                                        targetTemperatureInC: 21))
        }
    }
}
#endif
