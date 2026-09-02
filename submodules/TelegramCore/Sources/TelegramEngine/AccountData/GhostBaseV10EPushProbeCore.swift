import Foundation

enum GhostBaseV10EPushProbeCore {
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
    static func count(_ name: String) -> Int {
        return UserDefaults.standard.integer(forKey: "jerkgram.V10E.Push." + name + ".Count")
    }

    static func typeStatus(prefix: String) -> String {
        let request = count(prefix + "Request")
        let success = count(prefix + "Success")
        let invalidated = count(prefix + "Invalidated")
        let error = count(prefix + "Error")

        if success > 0 {
            return "success"
        } else if invalidated > 0 {
            return "invalidated"
        } else if error > 0 {
            return "error"
        } else if request > 0 {
            return "requested"
        } else {
            return "not-seen"
        }
    }

    static func setRegisterDeviceTypeSummary(lastType: Int32, kind: String) {
        let t1Entry = count("registerDeviceType1Entry")
        let t1Request = count("registerDeviceType1Request")
        let t1Success = count("registerDeviceType1Success")
        let t1Invalidated = count("registerDeviceType1Invalidated")
        let t1Error = count("registerDeviceType1Error")

        let t9Entry = count("registerDeviceType9Entry")
        let t9Request = count("registerDeviceType9Request")
        let t9Success = count("registerDeviceType9Success")
        let t9Invalidated = count("registerDeviceType9Invalidated")
        let t9Error = count("registerDeviceType9Error")

        let t1Status = typeStatus(prefix: "registerDeviceType1")
        let t9Status = typeStatus(prefix: "registerDeviceType9")

        let summary = "last=\(lastType)/\(kind); type1=\(t1Status) E/R/S/I/ERR=\(t1Entry)/\(t1Request)/\(t1Success)/\(t1Invalidated)/\(t1Error); type9=\(t9Status) E/R/S/I/ERR=\(t9Entry)/\(t9Request)/\(t9Success)/\(t9Invalidated)/\(t9Error)"
        set("LastRegisterDeviceType", summary)
    }

}
