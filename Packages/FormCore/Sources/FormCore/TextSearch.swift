import Foundation

/// Fast local text matching for food and exercise search.
public enum TextSearch {

    /// How well a name matches a query. Higher is better; `nil` means no match.
    public enum MatchQuality: Int, Comparable, Sendable {
        /// Query appears inside a word.
        case contains = 1
        /// A word in the name starts with the query.
        case wordPrefix = 2
        /// The name starts with the query.
        case prefix = 3
        /// The name equals the query.
        case exact = 4

        public static func < (lhs: MatchQuality, rhs: MatchQuality) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Case- and diacritic-insensitive partial match. Every whitespace-separated
    /// term of the query must appear in the name ("greek yog" matches
    /// "Yoghurt, Greek style"). An empty query matches everything as `.contains`.
    public static func match(_ name: String, query: String, locale: Locale = .current) -> MatchQuality? {
        let normalizedQuery = normalize(query, locale: locale)
        if normalizedQuery.isEmpty { return .contains }
        let normalizedName = normalize(name, locale: locale)

        let terms = normalizedQuery.split(separator: " ").map(String.init)
        guard terms.allSatisfy({ normalizedName.contains($0) }) else { return nil }

        if normalizedName == normalizedQuery { return .exact }
        if normalizedName.hasPrefix(normalizedQuery) { return .prefix }
        let words = normalizedName.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if let first = terms.first, words.contains(where: { $0.hasPrefix(first) }) { return .wordPrefix }
        return .contains
    }

    /// Filters and orders `items` by match quality, then by `name` alphabetically.
    public static func rank<T>(_ items: [T], query: String, name: (T) -> String, locale: Locale = .current) -> [T] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items
            .compactMap { item -> (T, MatchQuality, String)? in
                let itemName = name(item)
                guard let quality = match(itemName, query: trimmed, locale: locale) else { return nil }
                return (item, quality, itemName)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.2.localizedCaseInsensitiveCompare(rhs.2) == .orderedAscending
            }
            .map { $0.0 }
    }

    static func normalize(_ text: String, locale: Locale) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
