import Foundation

/// Keep this in sync with `/docs` pages so in-app and web legal content match.
enum AppLegalContent {
    static let effectiveDate = "March 4, 2026"

    static let legalHomeURL = URL(string: "https://harimalar.github.io/Clean-Fast/")!
    static let privacyURL = URL(string: "https://harimalar.github.io/Clean-Fast/privacy.html")!
    static let termsURL = URL(string: "https://harimalar.github.io/Clean-Fast/terms.html")!
    static let medicalURL = URL(string: "https://harimalar.github.io/Clean-Fast/medical-disclaimer.html")!

    static let medicalSummary = "ClearFast is an educational wellness tool and not a medical device."
    static let urgentWarning = "Stop fasting and seek medical care if you feel unwell."

    static let medicalBody = "Consult your doctor before fasting, especially with diabetes, medication use, pregnancy, breastfeeding, age under 18, or any medical condition."

    static let privacySummary = "ClearFast stores fasting goals, history, and preferences on device, with optional iCloud sync. ClearFast does not sell personal data."

    static let termsSummary = "ClearFast provides educational wellness tracking. You are responsible for your fasting decisions and should seek medical advice before prolonged fasts."
}
