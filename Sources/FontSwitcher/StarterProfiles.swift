import FontSwitcherCore

/// First-run profiles are copied into the user's editable profile collection once.
enum StarterProfiles {
    static let all: [Profile] = [
        Profile(name: "Work", family: "SF Mono", size: 14),
        Profile(name: "Coding", family: "Menlo", size: 13),
        Profile(name: "Design", family: "Monaco", size: 16),
    ]

    static func summary(for name: String) -> String? {
        switch name {
        case "Work": "Balanced and comfortable for the everyday"
        case "Coding": "Compact and crisp for dense code"
        case "Design": "A roomier view for visual work"
        default: nil
        }
    }
}
