import Foundation

enum GhostBaseV10EPushProbe {
    static func record(_ name: String, amount: Int = 1) {
        guard amount > 0 else {
            return
        }
        let defaults = UserDefaults.standard
        let prefix = "jerkgram.V10E.Push."
        let key = prefix + name + ".Count"
        defaults.set(defaults.integer(forKey: key) + amount, forKey: key)
        defaults.set(defaults.integer(forKey: prefix + "Total") + amount, forKey: prefix + "Total")
        defaults.set(name, forKey: prefix + "Last")
        defaults.set(amount, forKey: prefix + "LastAmount")
        defaults.set(Int(Date().timeIntervalSince1970), forKey: prefix + "LastTime")
    }

    static func set(_ key: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: "jerkgram.V10E.Push." + key)
    }

    static func preview(_ value: String, limit: Int = 160) -> String {
        if value.count <= limit {
            return value
        }
        return String(value.prefix(limit))
    }
}
