public let backlogMost = 16

public struct Stream {
    private var backlog: Int
    private var pending: Int

    public init?(backlog: Int) {
        guard backlog <= backlogMost else { return nil }
        self.backlog = backlog
        pending = 0
    }

    public mutating func accept() -> Bool {
        let room = pending < backlog
        if room { pending += 1 }
        return room
    }
}
