import Testing
@testable import RunQueue

@Test func peeks() {
    var queue = RunQueue(limit: 1)
    queue.head = 3
    queue.items.append(1)
    #expect(queue.items.count == 1)
}
