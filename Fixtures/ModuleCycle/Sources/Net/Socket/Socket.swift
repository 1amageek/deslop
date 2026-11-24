public let backlogMost = 16

public func listen(_ backlog: Int) -> Stream? {
    Stream(backlog: backlog)
}
