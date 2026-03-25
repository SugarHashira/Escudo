import Foundation

// These enums were originally generated from a Siri Intent definition
// Widget intent types defined here since Escudo has no widget target.

enum TimePeriod: Int, CaseIterable {
    case unknown = 0
    case day     = 1
    case week    = 2
    case month   = 3
    case year    = 4
}

enum InsightsTimePeriod: Int, CaseIterable {
    case unknown = 0
    case week    = 1
    case month   = 2
    case year    = 3
}

enum InsightsType: Int, CaseIterable {
    case unknown = 0
    case expense = 1
    case income  = 2
    case net     = 3
}
