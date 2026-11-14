import Foundation

// Uses the existing per-account Settings scope. GRAM overrides never enter WalletContext.
public enum JerkgramLocalGramBalance {
    public static let enabledKey = "jerkgram.Gram.LocalBalance.Enabled"
    public static let amountKey = "jerkgram.Gram.LocalBalance.Amount"
    public static let changed = Notification.Name("JerkgramLocalGramBalanceChanged")

    public static func scopedKey(accountPeerId: Int64, key: String) -> String {
        return "jerkgram.account.\(accountPeerId).setting.\(key)"
    }

    public static func sanitize(_ text: String) -> String {
        return text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00a0}", with: "").replacingOccurrences(of: ",", with: ".")
    }

    public static func savedAmount(_ text: String) -> String? {
        let value = sanitize(text)
        guard !value.isEmpty, value.count <= 20, !value.hasSuffix("."),
            value.allSatisfy({ ("0"..."9").contains(String($0)) || $0 == "." }) else { return nil }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = Int64(parts[0].isEmpty ? "0" : String(parts[0])), whole >= 0 else { return nil }
        let result = String(whole) + (parts.count == 2 ? "." + String(parts[1].prefix(9)) : "")
        guard nanotokens(result) != nil else { return nil }
        return result
    }

    // Exact integer arithmetic: avoid Double rounding and reject native Int64 overflow.
    public static func nanotokens(_ canonical: String) -> Int64? {
        let parts = canonical.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = Int64(parts[0]), whole >= 0 else { return nil }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= 9, fraction.allSatisfy({ ("0"..."9").contains(String($0)) }) else { return nil }
        let fractional = Int64(fraction + String(repeating: "0", count: 9 - fraction.count)) ?? 0
        let (base, productOverflow) = whole.multipliedReportingOverflow(by: 1_000_000_000)
        let (result, sumOverflow) = base.addingReportingOverflow(fractional)
        return productOverflow || sumOverflow ? nil : result
    }

    public static func enabled(accountPeerId: Int64, defaults: UserDefaults = .standard) -> Bool {
        return defaults.bool(forKey: scopedKey(accountPeerId: accountPeerId, key: enabledKey))
    }

    public static func amount(accountPeerId: Int64, defaults: UserDefaults = .standard) -> String {
        return defaults.string(forKey: scopedKey(accountPeerId: accountPeerId, key: amountKey)).flatMap(savedAmount) ?? "0"
    }

    public static func visualBalance(accountPeerId: Int64, defaults: UserDefaults = .standard) -> Int64? {
        guard enabled(accountPeerId: accountPeerId, defaults: defaults) else { return nil }
        return nanotokens(amount(accountPeerId: accountPeerId, defaults: defaults))
    }

    public static func commit(accountPeerId: Int64, enabled: Bool, amount: String, defaults: UserDefaults = .standard) {
        guard let amount = savedAmount(amount) else { return }
        defaults.set(enabled, forKey: scopedKey(accountPeerId: accountPeerId, key: enabledKey))
        defaults.set(amount, forKey: scopedKey(accountPeerId: accountPeerId, key: amountKey))
        // A closing editor from account A must never replace account B's compatibility aliases.
        if (defaults.object(forKey: "jerkgram.Settings.ActiveProjectionAccount.V176") as? NSNumber)?.int64Value == accountPeerId {
            defaults.set(enabled, forKey: enabledKey)
            defaults.set(amount, forKey: amountKey)
        }
        NotificationCenter.default.post(name: changed, object: nil, userInfo: ["accountPeerId": NSNumber(value: accountPeerId)])
    }
}
