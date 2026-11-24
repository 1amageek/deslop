import DeslopModel

/// Which types inherit which, through any number of steps. The model's
/// chains of inheritance end, so every walk does.
struct Inheritance {
    private let model: Model
    private var known: [ItemID: Set<ItemID>] = [:]

    init(model: Model) {
        self.model = model
    }

    /// Whether `type` inherits `ancestor`'s implementation, directly or through others.
    mutating func inherits(_ type: ItemID, from ancestor: ItemID) -> Bool {
        type != ancestor && ancestors(of: type).contains(ancestor)
    }

    private mutating func ancestors(of type: ItemID) -> Set<ItemID> {
        if let found = known[type] { return found }
        var found: Set<ItemID> = []
        var pending = model.item(type).inherits
        while let next = pending.popLast() {
            if found.insert(next).inserted {
                pending.append(contentsOf: model.item(next).inherits)
            }
        }
        known[type] = found
        return found
    }
}
