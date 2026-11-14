import SwiftUI

extension MouseProfile {
    /// Used when the connected mouse isn't one we know and says it has side buttons, or doesn't say:
    /// the three extra buttons most mice have, on a plain drawing. It matches nothing; it is a fallback.
    static let generic = make(
        "generic", brand: "Other", name: "Five-button mouse",
        body: .plain, buttons: .wheelAndSides, kind: .fallback)

    /// For an unknown mouse that says it has three buttons: only the wheel click is spare.
    static let generic3 = make(
        "generic3", brand: "Other", name: "Three-button mouse",
        body: .plain, buttons: .wheel, kind: .fallback)

    /// For an unknown mouse that says it has two buttons: nothing is spare.
    static let generic2 = make(
        "generic2", brand: "Other", name: "Two-button mouse",
        body: MouseBody.plain.finished(.silver), buttons: .none, kind: .fallback,
        note: "This mouse reports only a left and a right button, so there is no spare button for the agent wheel. Open the wheel from the MouseHerdr menu bar icon.")
}
