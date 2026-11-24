/// Why a report is a problem, drawn under its notes: the shape of what it
/// found, at a size a reader takes in at once.
public enum Picture: Hashable, Sendable {
    /// Members that know each other in a circle, from its cheapest tie: each
    /// step's member knows the next step's, and the last step's the first's.
    /// `rest` says what of the whole the circle leaves out.
    case circle(steps: [Step], rest: String?)
    /// A field, `owner`'s, and the modules whose code works on it, with how
    /// many places in each, most first; then what of its other fields is
    /// known outside, and what is kept.
    case spread(owner: String, field: String, modules: [Spread], others: [String])
    /// How many functions a module shows and hides, and each list it is
    /// learned by that is longer than a reader holds in mind.
    case lists(shown: Int, hidden: Int, lists: [Bar])
    /// How much there is of what has a most: a directory's files and
    /// directories, a file's lines.
    case bar(label: String, length: Int, most: Int)

    /// A module's arm into a leaked field: how many places, and the module.
    public struct Spread: Hashable, Sendable {
        public var places: Int
        public var module: String

        public init(places: Int, module: String) {
            self.places = places
            self.module = module
        }
    }

    /// A named length.
    public struct Bar: Hashable, Sendable {
        public var name: String
        public var length: Int

        public init(name: String, length: Int) {
            self.name = name
            self.length = length
        }
    }
}
