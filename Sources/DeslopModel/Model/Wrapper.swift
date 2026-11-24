/// A function that adds nothing of its own.
public enum Wrapper: Hashable, Sendable {
    /// Calls `target` and nothing else, passing its parameters on. `fields`:
    /// the fields of `self` it calls that function on.
    case forwarder(target: ItemID, fields: [ItemID])
    /// Hands out or overwrites fields of `self`, computing nothing: `lent`
    /// are those it lends or overwrites, `copied` those whose values it only
    /// hands out. `toRead`: it overwrites nothing, so what it lends can only
    /// be read, and code that calls it does with the fields what it does with
    /// the call.
    case accessor(lent: [ItemID], copied: [ItemID], toRead: Bool)
}
