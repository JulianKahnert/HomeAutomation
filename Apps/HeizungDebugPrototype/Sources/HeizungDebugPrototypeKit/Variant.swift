import Foundation

/// One case per design candidate. Add a case instead of editing an existing one,
/// so earlier candidates stay comparable until a winner is picked.
public enum Variant: String, CaseIterable, Identifiable, Sendable {
    case timeline
    case roomCards
    case decisionLog
    case diagnosis
    case skizzeV3
    case final
    case light
    case fireplaceRow
    case fireplaceButton
    case fireplaceDetail
    case fireplaceToolbar

    public var id: String { rawValue }

    /// Shown in the Variants menu, the window title, and the screenshot file name.
    public var title: String {
        switch self {
        case .timeline: "A Zeitleiste"
        case .roomCards: "B Raumkarten"
        case .decisionLog: "C Entscheidungsprotokoll"
        case .diagnosis: "D Diagnose (Hybrid)"
        case .skizzeV3: "E Skizze v3"
        case .final: "F Final"
        case .light: "G Leicht"
        case .fireplaceRow: "H-A Kamin: Zeile unter Schlagzeile"
        case .fireplaceButton: "H-B Kamin: Flamme an der Schlagzeile"
        case .fireplaceDetail: "H-C Kamin: Kopf des Kaminzimmer-Details"
        case .fireplaceToolbar: "H-D Kamin: Toolbar-Knopf"
        }
    }
}
