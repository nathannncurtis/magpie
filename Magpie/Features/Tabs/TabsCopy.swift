/// The tabs screen strings, gathered in one place.
enum TabsCopy {
    /// "3 open".
    static func openCount(_ count: Int) -> String {
        "\(count) open"
    }

    /// "Archived · 12".
    static func archived(_ count: Int) -> String {
        "Archived · \(count)"
    }
}
