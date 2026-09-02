import Foundation

// MARK: Jerkgram v1.2G BUILD118_TEXT_DIFF1
public enum JerkgramTextDiffOperation: Equatable {
    case equal(String)
    case insert(String)
    case delete(String)
    case replace(old: String, new: String)
}

public enum JerkgramTextDiff {
    public static func diff(old: String, new: String) -> [JerkgramTextDiffOperation] {
        if old == new { return old.isEmpty ? [] : [.equal(old)] }
        let oldCharacters = Array(old)
        let newCharacters = Array(new)
        // Character is an extended grapheme cluster, so emoji/ZWJ sequences
        // and combining marks are never split into invalid fragments.
        guard oldCharacters.count * newCharacters.count <= 250_000 else {
            return [.replace(old: old, new: new)]
        }
        var table = Array(
            repeating: Array(repeating: 0, count: newCharacters.count + 1),
            count: oldCharacters.count + 1
        )
        if !oldCharacters.isEmpty && !newCharacters.isEmpty {
            for i in stride(from: oldCharacters.count - 1, through: 0, by: -1) {
                for j in stride(from: newCharacters.count - 1, through: 0, by: -1) {
                    table[i][j] = oldCharacters[i] == newCharacters[j]
                        ? table[i + 1][j + 1] + 1
                        : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }
        var primitive: [JerkgramTextDiffOperation] = []
        var i = 0
        var j = 0
        while i < oldCharacters.count || j < newCharacters.count {
            if i < oldCharacters.count, j < newCharacters.count,
               oldCharacters[i] == newCharacters[j] {
                primitive.append(.equal(String(oldCharacters[i])))
                i += 1
                j += 1
            } else if j < newCharacters.count,
                      i == oldCharacters.count || table[i][j + 1] >= table[i + 1][j] {
                primitive.append(.insert(String(newCharacters[j])))
                j += 1
            } else {
                primitive.append(.delete(String(oldCharacters[i])))
                i += 1
            }
        }
        return self.coalesce(primitive)
    }

    private static func coalesce(
        _ operations: [JerkgramTextDiffOperation]
    ) -> [JerkgramTextDiffOperation] {
        var grouped: [JerkgramTextDiffOperation] = []
        for operation in operations {
            switch (grouped.last, operation) {
            case let (.equal(lhs)?, .equal(rhs)):
                grouped[grouped.count - 1] = .equal(lhs + rhs)
            case let (.insert(lhs)?, .insert(rhs)):
                grouped[grouped.count - 1] = .insert(lhs + rhs)
            case let (.delete(lhs)?, .delete(rhs)):
                grouped[grouped.count - 1] = .delete(lhs + rhs)
            default:
                grouped.append(operation)
            }
        }
        var result: [JerkgramTextDiffOperation] = []
        var index = 0
        while index < grouped.count {
            if index + 1 < grouped.count,
               case let .delete(old) = grouped[index],
               case let .insert(new) = grouped[index + 1] {
                result.append(.replace(old: old, new: new))
                index += 2
            } else if index + 1 < grouped.count,
                      case let .insert(new) = grouped[index],
                      case let .delete(old) = grouped[index + 1] {
                result.append(.replace(old: old, new: new))
                index += 2
            } else {
                result.append(grouped[index])
                index += 1
            }
        }
        return result
    }
}
