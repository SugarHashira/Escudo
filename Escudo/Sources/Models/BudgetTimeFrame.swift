import Foundation

enum BudgetTimeFrame: String, CaseIterable {
    case day = "Daily"
    case week = "Weekly"
    case month = "Monthly"
    case year = "Yearly"
    case custom = "Custom"

    var timeFrameString: String {
        switch self {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        case .custom: return "custom"
        }
    }
}
