/// Why a model cannot be read or does not hold.
public enum ModelError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The text is not JSON of the model's shape.
    case malformed(String)
    /// The document is not a `deslop-model` of a version this reads.
    case unsupportedFormat(format: String, version: Int)
    /// The first node is not the workspace root, or another node has no parent.
    case misplacedRoot(node: Int)
    /// A node's parent does not precede it.
    case parentAfterChild(node: Int, parent: Int)
    /// `field` of the `index`th `part` names `value`, which does not exist.
    case dangling(part: String, index: Int, field: String, value: Int)
    /// An item's chain of parents comes back to it.
    case parentCycle(item: Int)
    /// A chain of forwarders comes back to where it started.
    case forwarderCycle(function: Int)
    /// A line number below 1.
    case invalidLine(reference: Int, line: Int)
    /// A module whose parent is no package or module.
    case moduleOutsidePackage(node: Int)
    /// A node with the same parent, kind and name as an earlier one.
    case duplicateNode(node: Int)
    /// The language's path separator is empty, so names would run together.
    case emptyPathSeparator
    /// A file whose path is empty or absolute, whose lines are negative, or whose rank is not 0 to 3.
    case invalidFile(file: Int)
    /// A function with more than one wrapper entry.
    case duplicateWrapper(function: Int)

    public var description: String {
        switch self {
        case .malformed(let reason):
            "not a model: \(reason)"
        case .unsupportedFormat(let format, let version):
            "unsupported model format `\(format)` version \(version); expected `deslop-model` version 1"
        case .misplacedRoot(let node):
            "node \(node): only the first node is the root, and it is the workspace"
        case .parentAfterChild(let node, let parent):
            "node \(node): its parent \(parent) does not precede it"
        case .dangling(let part, let index, let field, let value):
            "\(part) \(index): `\(field)` names \(value), which does not exist"
        case .parentCycle(let item):
            "item \(item): its chain of parents loops"
        case .forwarderCycle(let function):
            "wrapper \(function): its chain of forwarders loops"
        case .invalidLine(let reference, let line):
            "reference \(reference): line \(line) is below 1"
        case .moduleOutsidePackage(let node):
            "node \(node): a module is inside a package or a module"
        case .duplicateNode(let node):
            "node \(node): its parent already has a child of its kind and name"
        case .emptyPathSeparator:
            "the language's path separator is empty"
        case .invalidFile(let file):
            "file \(file): a path is relative and not empty, lines are 0 or more, and a rank is 0 to 3"
        case .duplicateWrapper(let function):
            "wrapper \(function): a function has one wrapper entry at most"
        }
    }
}
