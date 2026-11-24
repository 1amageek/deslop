/// What is reported of a circle: where its cheapest tie is, a note for each
/// tie, and a picture of the shortest circle through the cheapest.
struct CircleReport {
    /// A tie between two members: the user's and the used's names, as
    /// reports write them, and identities, which tell apart members that
    /// share a name, such as overloads.
    struct Named {
        let user: String
        let used: String
        let userIdentity: Int
        let usedIdentity: Int
        let tie: Tie
    }

    /// How a member of a circle was first reached: where the search starts, or by a tie.
    private enum Reached {
        case origin
        case by(Int)
    }

    let location: Location?
    let notes: [String]
    let picture: Picture

    /// The report of a circle of `members` `noun`s, by the ties between them.
    /// The ties of fewest items come first: they are the cheapest to cut.
    init(_ context: LintContext, verb: String, noun: String, members: Int, ties unsorted: [Named]) {
        let ties = unsorted.sorted { a, b in
            if a.tie.cost != b.tie.cost { return a.tie.cost < b.tie.cost }
            if a.user != b.user { return Text.precedes(a.user, b.user) }
            if a.used != b.used { return Text.precedes(a.used, b.used) }
            if a.userIdentity != b.userIdentity { return a.userIdentity < b.userIdentity }
            return a.usedIdentity < b.usedIdentity
        }
        var notes = ties.prefix(Text.heldInMind).map {
            $0.tie.note(context, verb: verb, user: $0.user, used: $0.used)
        }
        if ties.count > Text.heldInMind {
            notes.append("and \(Text.counted(ties.count - Text.heldInMind, "more tie"))")
        }
        let circle = CircleReport.shortestCircle(ties.map { ($0.userIdentity, $0.usedIdentity) })
        let steps = circle.map { ties[$0].tie.step(context, member: ties[$0].user) }
        let leftOut = [
            (members - circle.count, "more \(noun)"),
            (ties.count - circle.count, "more tie"),
        ]
        .filter { $0.0 > 0 }
        .map { Text.counted($0.0, $0.1) }
        let rest = leftOut.isEmpty ? nil : "not drawn: \(leftOut.joined(separator: ", "))"
        self.location = ties.first?.tie.site
        self.notes = notes
        self.picture = .circle(steps: steps, rest: rest)
    }

    /// The shortest circle through the first of `ties`, each by the
    /// identities of the two it ties: the indexes of the ties it takes, in order, the first
    /// first. Of two as short, it takes the cheaper ties, which come first.
    static func shortestCircle<Member: Hashable>(_ ties: [(user: Member, used: Member)]) -> [Int] {
        let (start, end) = ties[0]
        // By member, the tie it was first reached by, going out from `end`.
        var reached: [Member: Reached] = [end: .origin]
        var queue = [end]
        var head = 0
        while head < queue.count {
            let at = queue[head]
            head += 1
            if at == start { break }
            for (index, tie) in ties.enumerated() where tie.user == at && reached[tie.used] == nil {
                reached[tie.used] = .by(index)
                queue.append(tie.used)
            }
        }
        var circle: [Int] = []
        var at = start
        while case .by(let index)? = reached[at] {
            circle.append(index)
            at = ties[index].user
        }
        circle.append(0)
        return circle.reversed()
    }
}
