# Protocol-Oriented Design für SwitchDevice

## Einleitung

### Aktuelles Design

Das aktuelle `SwitchDevice`-Design basiert auf einer **Class-Hierarchie mit Vererbung**:

```swift
open class SwitchDevice: Codable, @unchecked Sendable, Validatable, Log {
    public let switchId: EntityId
    public let brightnessId: EntityId?
    public let colorTemperatureId: EntityId?
    public let rgbId: EntityId?
    public let skipColorTemperature: Bool

    // ... methods
}

// 6 Subklassen:
public final class IkeaLightBulbWhite: SwitchDevice, @unchecked Sendable { }
public final class GenericSwitch: SwitchDevice, @unchecked Sendable { }
public final class LightBulbDimmable: SwitchDevice, @unchecked Sendable { }
public final class LightBulbWhite: SwitchDevice, @unchecked Sendable { }
public final class LightBulbColored: SwitchDevice, @unchecked Sendable { }
public final class IkeaLightBulbColored: SwitchDevice, @unchecked Sendable { }
```

### Warum Class-based?

**Aktuelle Gründe für das Class-Design:**

1. **Codable Serialisierung**: Class-Hierarchien funktionieren nahtlos mit `Codable` für Konfigurationsdateien
2. **Konsistenz**: Alle Device-Typen im Codebase nutzen das gleiche Pattern (MotionSensorDevice, ContactSensorDevice, HeatSwitchDevice, etc.)
3. **Polymorphismus**: Eine Subklasse (`IkeaLightBulbWhite`) überschreibt `turnOff()`-Verhalten
4. **Minimale Komplexität**: Nur 2-Level-Hierarchie mit klarer Struktur

**Herausforderungen des aktuellen Designs:**

1. **`@unchecked Sendable` erforderlich**: Weil `open class` nicht automatisch Sendable sein kann
2. **Warnings bei Subklassen**: Swift 6 verlangt Restatement von `@unchecked Sendable` in final classes
3. **5 von 6 Subklassen** sind nur Konfigurations-Wrapper (keine echte Verhaltensänderung)
4. **Nicht idiomatisch Swift**: Swift bevorzugt protocol-oriented programming

### Wann ist ein Protocol-oriented Redesign sinnvoll?

Ein Redesign sollte in Betracht gezogen werden, wenn:

- ✅ Mehrere Device-Typen gleichzeitig umgestellt werden
- ✅ Neue Devices mit unterschiedlichem Verhalten häufig hinzukommen
- ✅ Die `@unchecked Sendable`-Warnings problematisch werden
- ✅ Testbarkeit wichtiger wird (Protocols sind leichter zu mocken)
- ✅ Codable-Komplexität akzeptabel ist

**NICHT sinnvoll, wenn:**

- ❌ Nur SwitchDevice betroffen ist (Inkonsistenz mit Rest des Codebases)
- ❌ Codable-Einfachheit kritisch ist
- ❌ Wenige neue Device-Varianten erwartet werden
- ❌ Aktuelle Lösung gut funktioniert

---

## Ansatz 2: Enum-based Configuration

### Konzept

Ersetze die Class-Hierarchie durch eine **einzige Struct** mit einem **Enum für unterschiedliche Verhaltensweisen**.

### Vollständige Implementierung

```swift
// MARK: - TurnOffBehavior Enum

/// Definiert verschiedene Strategien zum Ausschalten von Devices
public enum TurnOffBehavior: Sendable, Codable {
    /// Standard: Nutzt den Power Switch
    case standard

    /// IKEA-spezifisch: Setzt Helligkeit auf 0
    /// (einige IKEA Bulbs schalten nicht richtig mit turnOff aus)
    case ikea
}

// MARK: - SwitchDevice Struct

public struct SwitchDevice: Sendable, Codable, Validatable, Log {
    public let switchId: EntityId
    public let brightnessId: EntityId?
    public let colorTemperatureId: EntityId?
    public let rgbId: EntityId?
    public let skipColorTemperature: Bool
    public let turnOffBehavior: TurnOffBehavior

    /// Vollständiger Initializer
    public init(
        switchId: EntityId,
        brightnessId: EntityId? = nil,
        colorTemperatureId: EntityId? = nil,
        rgbId: EntityId? = nil,
        skipColorTemperature: Bool = false,
        turnOffBehavior: TurnOffBehavior = .standard
    ) {
        self.switchId = switchId
        self.brightnessId = brightnessId
        self.colorTemperatureId = colorTemperatureId
        self.rgbId = rgbId
        self.skipColorTemperature = skipColorTemperature
        self.turnOffBehavior = turnOffBehavior
    }

    // MARK: - Control Methods

    public func turnOn(with hm: HomeManagable) async {
        await hm.perform(.turnOn(switchId))
    }

    public func turnOff(with hm: HomeManagable) async {
        switch turnOffBehavior {
        case .standard:
            await hm.perform(.turnOff(switchId))

        case .ikea:
            // IKEA-spezifisches Verhalten: Brightness auf 0 setzen
            if let brightnessId {
                await hm.perform(.setBrightness(brightnessId, 0))
            } else {
                // Fallback wenn keine Brightness verfügbar
                await hm.perform(.turnOff(switchId))
            }
        }
    }

    public func setBrightness(to value: Float, with hm: HomeManagable) async {
        guard let brightnessId else { return }
        await hm.perform(.setBrightness(brightnessId, value))
    }

    public func setColorTemperature(to value: Float, with hm: any HomeManagable) async {
        guard !skipColorTemperature else {
            log.debug("Skipping color temperature for device: \(switchId) (Adaptive Lighting)")
            return
        }

        assert((0...1).contains(value))

        guard hasColorTemperatureSupport else {
            log.warning("setColorTemperature called on device without support: \(switchId)")
            return
        }

        if let colorTemperatureId {
            await hm.perform(.setColorTemperature(colorTemperatureId, value))
        } else if let rgbId {
            let rgb = componentsForColorTemperature(normalzied: value)
            await hm.perform(.setRGB(rgbId, rgb: rgb))
        }
    }

    public func setColor(to rgb: RGB, with hm: any HomeManagable) async {
        guard let rgbId else { return }
        await hm.perform(.setRGB(rgbId, rgb: rgb))
    }

    // MARK: - Properties

    public var hasColorTemperatureSupport: Bool {
        !skipColorTemperature && (colorTemperatureId != nil || rgbId != nil)
    }

    // MARK: - Validation

    public func validate(with hm: HomeManagable) async throws {
        try await hm.findEntity(switchId)
        if let brightnessId {
            try await hm.findEntity(brightnessId)
        }
        if let colorTemperatureId {
            try await hm.findEntity(colorTemperatureId)
        }
        if let rgbId {
            try await hm.findEntity(rgbId)
        }
    }
}

// MARK: - Factory Methods

extension SwitchDevice {
    /// Generischer Switch ohne Dimmen/Farbe
    public static func genericSwitch(
        query: EntityId.Query,
        skipColorTemperature: Bool = false
    ) -> SwitchDevice {
        SwitchDevice(
            switchId: EntityId(query: query, characteristic: .switcher),
            brightnessId: nil,
            colorTemperatureId: nil,
            rgbId: nil,
            skipColorTemperature: skipColorTemperature,
            turnOffBehavior: .standard
        )
    }

    /// Dimmbares Licht (ohne Farbsteuerung)
    public static func lightBulbDimmable(
        query: EntityId.Query,
        skipColorTemperature: Bool = false
    ) -> SwitchDevice {
        SwitchDevice(
            switchId: EntityId(query: query, characteristic: .switcher),
            brightnessId: EntityId(query: query, characteristic: .brightness),
            colorTemperatureId: nil,
            rgbId: nil,
            skipColorTemperature: skipColorTemperature,
            turnOffBehavior: .standard
        )
    }

    /// Weißes Licht mit Farbtemperatur-Steuerung
    public static func lightBulbWhite(
        query: EntityId.Query,
        skipColorTemperature: Bool = false
    ) -> SwitchDevice {
        SwitchDevice(
            switchId: EntityId(query: query, characteristic: .switcher),
            brightnessId: EntityId(query: query, characteristic: .brightness),
            colorTemperatureId: EntityId(query: query, characteristic: .colorTemperature),
            rgbId: nil,
            skipColorTemperature: skipColorTemperature,
            turnOffBehavior: .standard
        )
    }

    /// Vollfarbiges Licht mit RGB und Farbtemperatur
    public static func lightBulbColored(
        query: EntityId.Query,
        skipColorTemperature: Bool = false
    ) -> SwitchDevice {
        SwitchDevice(
            switchId: EntityId(query: query, characteristic: .switcher),
            brightnessId: EntityId(query: query, characteristic: .brightness),
            colorTemperatureId: EntityId(query: query, characteristic: .colorTemperature),
            rgbId: EntityId(query: query, characteristic: .color),
            skipColorTemperature: skipColorTemperature,
            turnOffBehavior: .standard
        )
    }

    /// IKEA weißes Licht (nutzt Brightness-Control für turnOff)
    public static func ikeaLightBulbWhite(
        query: EntityId.Query,
        skipColorTemperature: Bool = false
    ) -> SwitchDevice {
        SwitchDevice(
            switchId: EntityId(query: query, characteristic: .switcher),
            brightnessId: EntityId(query: query, characteristic: .brightness),
            colorTemperatureId: EntityId(query: query, characteristic: .colorTemperature),
            rgbId: nil,
            skipColorTemperature: skipColorTemperature,
            turnOffBehavior: .ikea  // ← UNTERSCHIED
        )
    }

    /// IKEA farbiges Licht (ohne dedizierte Farbtemperatur, nutzt RGB)
    public static func ikeaLightBulbColored(
        query: EntityId.Query,
        skipColorTemperature: Bool = false
    ) -> SwitchDevice {
        SwitchDevice(
            switchId: EntityId(query: query, characteristic: .switcher),
            brightnessId: EntityId(query: query, characteristic: .brightness),
            colorTemperatureId: nil,  // IKEA exposes no color temperature
            rgbId: EntityId(query: query, characteristic: .color),
            skipColorTemperature: skipColorTemperature,
            turnOffBehavior: .ikea  // ← UNTERSCHIED
        )
    }
}
```

### Verwendung

```swift
// Alte Verwendung (Class-based):
let light = IkeaLightBulbWhite(query: .init(room: "Kitchen", device: "Ceiling Light"))

// Neue Verwendung (Factory Method):
let light = SwitchDevice.ikeaLightBulbWhite(query: .init(room: "Kitchen", device: "Ceiling Light"))

// In Automations:
public struct MotionAtNight: Automatable {
    public let lights: [SwitchDevice]  // Bleibt gleich!

    public init(name: String, lights: [SwitchDevice], /* ... */) {
        self.lights = lights
        // ...
    }
}

// Konfiguration:
let automation = MotionAtNight(
    name: "Kitchen Night",
    lights: [
        .ikeaLightBulbWhite(query: .init(room: "Kitchen", device: "Ceiling")),
        .lightBulbDimmable(query: .init(room: "Kitchen", device: "Counter"))
    ],
    // ...
)
```

### Codable

**Vorteil:** Funktioniert automatisch out-of-the-box!

```swift
// Serialisierung
let device = SwitchDevice.ikeaLightBulbWhite(
    query: .init(room: "Kitchen", device: "Light")
)
let json = try JSONEncoder().encode(device)

// Deserialisierung
let decoded = try JSONDecoder().decode(SwitchDevice.self, from: json)
```

JSON-Ausgabe:
```json
{
  "switchId": "...",
  "brightnessId": "...",
  "colorTemperatureId": "...",
  "rgbId": null,
  "skipColorTemperature": false,
  "turnOffBehavior": "ikea"
}
```

### Migration Path

#### Phase 1: Preparation (1-2 Tage)
1. Neue `SwitchDevice` struct in separatem File erstellen
2. Factory methods hinzufügen
3. Tests für neue Implementierung schreiben
4. Codable Serialization/Deserialization testen

#### Phase 2: Migration (3-5 Tage)
1. Alte Class in `SwitchDeviceLegacy` umbenennen
2. Neue Struct als `SwitchDevice` verfügbar machen
3. Alle Instantiierungen zu Factory Methods migrieren:
   ```swift
   // Vorher:
   IkeaLightBulbWhite(query: query)

   // Nachher:
   SwitchDevice.ikeaLightBulbWhite(query: query)
   ```
4. Compiler-Fehler beheben

#### Phase 3: Testing (2-3 Tage)
1. Unit Tests ausführen
2. Integration Tests mit echten Devices
3. Codable Roundtrip Tests (encode → decode → verify)

#### Phase 4: Cleanup (1 Tag)
1. Alte Class-Files löschen
2. `SwitchDeviceLegacy` entfernen
3. Dokumentation aktualisieren

**Geschätzter Gesamtaufwand:** 7-11 Tage

### Vor- und Nachteile

#### Vorteile ✅

1. **Kein `@unchecked Sendable`**: Struct ist automatisch `Sendable` wenn alle Properties `Sendable` sind
2. **Keine Warnings**: Keine Compiler-Warnungen mehr
3. **Einfache Codable**: Out-of-the-box ohne custom Implementation
4. **Klare Intent**: Factory Methods sind selbstdokumentierend
5. **Erweiterbar**: Neue Behaviors durch Enum-Cases hinzufügbar
6. **Immutability**: Structs fördern value semantics

#### Nachteile ❌

1. **Begrenzte Erweiterbarkeit**: Neue Behaviors benötigen Core-Code-Änderungen
2. **Logic in Struct**: Behavior-Logic liegt in `turnOff()` switch statement (nicht separation of concerns)
3. **Breaking Change**: Alle Instantiierungen müssen angepasst werden
4. **Inkonsistenz**: Nur SwitchDevice ist struct-based, andere Devices bleiben class-based
5. **Loss of Polymorphism**: Kein Override mehr möglich (aber auch nicht notwendig)

### Betroffene Dateien

#### Zu löschen:
- `Sources/HAModels/Entities/IkeaLightBulbWhite.swift`
- `Sources/HAImplementations/Entities/GenericSwitch.swift`
- `Sources/HAImplementations/Entities/LightBulbDimmable.swift`
- `Sources/HAImplementations/Entities/LightBulbWhite.swift`
- `Sources/HAImplementations/Entities/LightBulbColored.swift`
- `Sources/HAImplementations/Entities/IkeaLightBulbColored.swift`

#### Zu ändern:
- `Sources/HAModels/Entities/SwitchDevice.swift` (komplett neu)
- Alle Automations die Devices instantiieren (~10-15 Dateien):
  - `Sources/HAImplementations/Automations/MotionAtNight.swift`
  - `Sources/HAImplementations/Automations/Turn.swift`
  - `Sources/HAImplementations/Automations/TurnOnForDuration.swift`
  - `Sources/HAImplementations/Automations/EnergyLowPrice.swift`
  - `Sources/HAImplementations/Automations/CreateScene.swift`
  - Weitere Konfigurationsdateien

---

## Ansatz 3: Hybrid - Final Class mit Behavior Protocol

### Konzept

Behalte die Class-Struktur, mache sie aber `final` und nutze **Composition über Inheritance** für unterschiedliche Verhaltensweisen.

### Vollständige Implementierung

```swift
// MARK: - Behavior Protocol

/// Protocol für unterschiedliche turnOff-Strategien
public protocol TurnOffBehavior: Sendable {
    func execute(switchId: EntityId, brightnessId: EntityId?, with hm: HomeManagable) async
}

// MARK: - Concrete Behaviors

/// Standard turnOff: Nutzt Power Switch
public struct StandardTurnOffBehavior: TurnOffBehavior, Codable {
    public init() {}

    public func execute(switchId: EntityId, brightnessId: EntityId?, with hm: HomeManagable) async {
        await hm.perform(.turnOff(switchId))
    }
}

/// IKEA turnOff: Setzt Brightness auf 0
public struct IkeaTurnOffBehavior: TurnOffBehavior, Codable {
    public init() {}

    public func execute(switchId: EntityId, brightnessId: EntityId?, with hm: HomeManagable) async {
        if let brightnessId {
            await hm.perform(.setBrightness(brightnessId, 0))
        } else {
            // Fallback
            await hm.perform(.turnOff(switchId))
        }
    }
}

// MARK: - Behavior Container (für Codable)

/// Wrapper für TurnOffBehavior um Codable zu unterstützen
public enum TurnOffBehaviorContainer: Sendable, Codable {
    case standard(StandardTurnOffBehavior)
    case ikea(IkeaTurnOffBehavior)

    var behavior: any TurnOffBehavior {
        switch self {
        case .standard(let behavior):
            return behavior
        case .ikea(let behavior):
            return behavior
        }
    }

    // Codable implementation
    enum CodingKeys: String, CodingKey {
        case type, behavior
    }

    enum BehaviorType: String, Codable {
        case standard, ikea
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(BehaviorType.self, forKey: .type)

        switch type {
        case .standard:
            let behavior = try container.decode(StandardTurnOffBehavior.self, forKey: .behavior)
            self = .standard(behavior)
        case .ikea:
            let behavior = try container.decode(IkeaTurnOffBehavior.self, forKey: .behavior)
            self = .ikea(behavior)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .standard(let behavior):
            try container.encode(BehaviorType.standard, forKey: .type)
            try container.encode(behavior, forKey: .behavior)
        case .ikea(let behavior):
            try container.encode(BehaviorType.ikea, forKey: .type)
            try container.encode(behavior, forKey: .behavior)
        }
    }
}

// MARK: - SwitchDevice (Final Class)

public final class SwitchDevice: Codable, Sendable, Validatable, Log {
    public let switchId: EntityId
    public let brightnessId: EntityId?
    public let colorTemperatureId: EntityId?
    public let rgbId: EntityId?
    public let skipColorTemperature: Bool

    // Behavior durch Composition
    private let turnOffBehaviorContainer: TurnOffBehaviorContainer

    public init(
        switchId: EntityId,
        brightnessId: EntityId? = nil,
        colorTemperatureId: EntityId? = nil,
        rgbId: EntityId? = nil,
        skipColorTemperature: Bool = false,
        turnOffBehavior: TurnOffBehaviorContainer = .standard(StandardTurnOffBehavior())
    ) {
        self.switchId = switchId
        self.brightnessId = brightnessId
        self.colorTemperatureId = colorTemperatureId
        self.rgbId = rgbId
        self.skipColorTemperature = skipColorTemperature
        self.turnOffBehaviorContainer = turnOffBehavior
    }

    // MARK: - Control Methods

    public func turnOn(with hm: HomeManagable) async {
        await hm.perform(.turnOn(switchId))
    }

    public func turnOff(with hm: HomeManagable) async {
        // Delegate zu Behavior
        await turnOffBehaviorContainer.behavior.execute(
            switchId: switchId,
            brightnessId: brightnessId,
            with: hm
        )
    }

    public func setBrightness(to value: Float, with hm: HomeManagable) async {
        guard let brightnessId else { return }
        await hm.perform(.setBrightness(brightnessId, value))
    }

    public func setColorTemperature(to value: Float, with hm: any HomeManagable) async {
        guard !skipColorTemperature else {
            log.debug("Skipping color temperature for device: \(switchId) (Adaptive Lighting)")
            return
        }

        assert((0...1).contains(value))

        guard hasColorTemperatureSupport else {
            log.warning("setColorTemperature called on device without support: \(switchId)")
            return
        }

        if let colorTemperatureId {
            await hm.perform(.setColorTemperature(colorTemperatureId, value))
        } else if let rgbId {
            let rgb = componentsForColorTemperature(normalzied: value)
            await hm.perform(.setRGB(rgbId, rgb: rgb))
        }
    }

    public func setColor(to rgb: RGB, with hm: any HomeManagable) async {
        guard let rgbId else { return }
        await hm.perform(.setRGB(rgbId, rgb: rgb))
    }

    // MARK: - Properties

    public var hasColorTemperatureSupport: Bool {
        !skipColorTemperature && (colorTemperatureId != nil || rgbId != nil)
    }

    // MARK: - Validation

    public func validate(with hm: HomeManagable) async throws {
        try await hm.findEntity(switchId)
        if let brightnessId {
            try await hm.findEntity(brightnessId)
        }
        if let colorTemperatureId {
            try await hm.findEntity(colorTemperatureId)
        }
        if let rgbId {
            try await hm.findEntity(rgbId)
        }
    }
}

// MARK: - Factory Methods

extension SwitchDevice {
    public static func genericSwitch(
        query: EntityId.Query,
        skipColorTemperature: Bool = false
    ) -> SwitchDevice {
        SwitchDevice(
            switchId: EntityId(query: query, characteristic: .switcher),
            brightnessId: nil,
            colorTemperatureId: nil,
            rgbId: nil,
            skipColorTemperature: skipColorTemperature,
            turnOffBehavior: .standard(StandardTurnOffBehavior())
        )
    }

    public static func ikeaLightBulbWhite(
        query: EntityId.Query,
        skipColorTemperature: Bool = false
    ) -> SwitchDevice {
        SwitchDevice(
            switchId: EntityId(query: query, characteristic: .switcher),
            brightnessId: EntityId(query: query, characteristic: .brightness),
            colorTemperatureId: EntityId(query: query, characteristic: .colorTemperature),
            rgbId: nil,
            skipColorTemperature: skipColorTemperature,
            turnOffBehavior: .ikea(IkeaTurnOffBehavior())  // ← UNTERSCHIED
        )
    }

    // ... weitere factory methods
}
```

### Codable

**Herausforderung:** Protocol-basierte Behaviors benötigen Custom Codable!

Die Lösung verwendet ein `TurnOffBehaviorContainer` enum das als Type-safe wrapper fungiert.

JSON-Ausgabe:
```json
{
  "switchId": "...",
  "brightnessId": "...",
  "colorTemperatureId": "...",
  "rgbId": null,
  "skipColorTemperature": false,
  "turnOffBehaviorContainer": {
    "type": "ikea",
    "behavior": {}
  }
}
```

### Vor- und Nachteile

#### Vorteile ✅

1. **`Sendable` ohne `@unchecked`**: `final class` kann regulär `Sendable` sein
2. **Keine Warnings**: Keine Compiler-Warnungen
3. **Erweiterbar**: Neue Behaviors durch neue Structs hinzufügen
4. **Separation of Concerns**: Behavior-Logic ist in separaten Types
5. **Weniger Breaking Changes**: Kann schrittweise eingeführt werden
6. **Testbar**: Behaviors können einzeln getestet werden

#### Nachteile ❌

1. **Komplexe Codable**: Custom Codable-Implementierung für BehaviorContainer
2. **Immer noch Class-based**: Nicht vollständig protocol-oriented
3. **Boilerplate**: Container enum + protocol + concrete types = mehr Code
4. **Performance**: Indirection durch protocol witness table (minimal)
5. **Inkonsistenz**: Nur SwitchDevice nutzt dieses Pattern

### Betroffene Dateien

Identisch zu Ansatz 2.

---

## Vergleich der Ansätze

| Kriterium | Ansatz 2 (Enum) | Ansatz 3 (Hybrid) | Ansatz 4 (Status Quo) |
|-----------|----------------|-------------------|----------------------|
| **Sendable** | ✅ Automatisch | ✅ Ohne `@unchecked` | ⚠️ `@unchecked` |
| **Codable** | ✅ Out-of-box | ⚠️ Custom impl. | ✅ Out-of-box |
| **Erweiterbarkeit** | ⚠️ Core changes | ✅ Neue Structs | ⚠️ Neue Subklassen |
| **Complexity** | ✅ Einfach | ⚠️ Mittel | ✅ Minimal |
| **Breaking Changes** | ❌ Viele | ⚠️ Moderat | ✅ Keine |
| **POP Konformität** | ✅ Sehr gut | ⚠️ Mittel | ❌ Class-based |
| **Konsistenz** | ❌ Nur SwitchDevice | ❌ Nur SwitchDevice | ✅ Alle Devices |
| **Aufwand** | 7-11 Tage | 10-14 Tage | 1 Stunde |

## Empfehlung

### Für dieses Projekt: **Status Quo (Ansatz 4)**

**Begründung:**

1. **Nur SwitchDevice betroffen**: Andere Device-Typen bleiben class-based → Inkonsistenz
2. **Codable-Einfachheit kritisch**: Konfigurationsdateien müssen einfach serialisierbar bleiben
3. **Minimale Polymorphismus-Nutzung**: Nur 1 von 6 Subklassen überschreibt Verhalten
4. **Funktioniert gut**: Das aktuelle Design hat keine funktionalen Probleme
5. **Minimal effort**: `@unchecked Sendable` zu Subklassen hinzufügen löst Warnings

**Wann anders entscheiden:**

- ✅ **Ansatz 2 (Enum)** → Wenn gesamte Device-Architektur gleichzeitig umgestellt wird
- ✅ **Ansatz 3 (Hybrid)** → Wenn viele unterschiedliche Behaviors hinzukommen und Erweiterbarkeit wichtig wird

### Langfristige Vision

Falls eine vollständige Architektur-Migration gewünscht ist:

1. **Phase 1**: Ansatz 2 für SwitchDevice implementieren
2. **Phase 2**: Evaluate pattern für andere Device-Typen
3. **Phase 3**: Migriere MotionSensorDevice, ContactSensorDevice, etc. zu gleichem Pattern
4. **Phase 4**: Einheitliches struct-based Device-System

**Geschätzter Gesamtaufwand:** 4-6 Wochen für alle Device-Typen

---

## Migration Strategy (falls umgesetzt)

### Vorbereitung

1. **Spike/Proof-of-Concept** (1-2 Tage)
   - Implementiere einen einzelnen Device-Typ mit neuem Pattern
   - Teste Codable Serialization/Deserialization
   - Verifiziere Performance-Charakteristik

2. **Documentation** (1 Tag)
   - Dokumentiere neues Pattern
   - Erstelle Migration Guide für Team
   - Update Architecture Decision Records (ADR)

### Implementation

**Iterativer Ansatz (empfohlen):**

1. Neue Implementation parallel zur alten erstellen
2. Tests für neue Implementation schreiben
3. Schrittweise Migration File für File
4. Alte Implementation deprecaten
5. Nach 1-2 Releases: Alte Implementation entfernen

**Big Bang Ansatz (nicht empfohlen):**

1. Alle Files gleichzeitig ändern
2. Hoher Risk von Breaking Changes
3. Schwierige Code Reviews

### Test Strategy

1. **Unit Tests**
   - Teste alle Factory Methods
   - Teste unterschiedliche Behaviors
   - Teste Codable Roundtrips

2. **Integration Tests**
   - Teste mit echten HomeKit Devices
   - Teste Automation Flows end-to-end
   - Teste Configuration Loading

3. **Regression Tests**
   - Ensure alte Config-Dateien laden noch
   - Ensure Behavior ist identisch zu vorher

### Backwards Compatibility

**Option A: Dual Support (empfohlen)**

Beide Implementierungen parallel unterstützen für 1-2 Releases:

```swift
// Codable kann beide Formate lesen
public struct SwitchDeviceDecoder {
    func decode(from data: Data) throws -> SwitchDevice {
        // Try new format first
        if let device = try? JSONDecoder().decode(SwitchDevice.self, from: data) {
            return device
        }

        // Fallback to legacy format
        let legacyDevice = try JSONDecoder().decode(SwitchDeviceLegacy.self, from: data)
        return legacyDevice.migrated()
    }
}
```

**Option B: Migration Script**

One-time migration von allen Config-Dateien:

```swift
func migrateConfigFiles() {
    // Find all config files
    // Load, convert, save in new format
    // Backup old files
}
```

---

## Fazit

Die **Class-based Hierarchie** ist für dieses Projekt **aktuell die richtige Wahl**:

- ✅ Funktioniert zuverlässig
- ✅ Codable ist trivial
- ✅ Konsistent mit Rest des Codebases
- ✅ Minimaler Maintenance-Aufwand

Ein **Protocol-oriented Redesign** sollte nur in Betracht gezogen werden, wenn:

- Alle Device-Typen gleichzeitig migriert werden
- Viele neue Device-Varianten mit unterschiedlichen Behaviors erwartet werden
- Die Team-Größe eine größere Refactoring-Initiative erlaubt
- Codable-Komplexität akzeptiert werden kann

**Entscheidung dokumentiert am:** 2025-12-16
