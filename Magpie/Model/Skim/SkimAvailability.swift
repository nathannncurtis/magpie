import FoundationModels

/// Whether Skim can run on this device. The one gate every Skim surface reads:
/// where this is unavailable, no Skim entry point is shown at all.
enum SkimAvailability: Equatable, Sendable {

    case available
    case unavailable

    static func resolve() -> SkimAvailability {
        SystemLanguageModel.default.availability == .available ? .available : .unavailable
    }

    var isAvailable: Bool { self == .available }
}
