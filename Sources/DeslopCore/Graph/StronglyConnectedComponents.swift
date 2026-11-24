/// Strongly connected components: the sets of nodes in which each reaches
/// every other (Tarjan's algorithm, with a stack of its own instead of
/// recursion, so a long chain cannot overflow the thread's).
public enum StronglyConnectedComponents {
    /// Each component of two or more nodes, sorted, in order of their first
    /// node. `edges[node]` are the nodes `node` reaches in one step.
    public static func circles(_ edges: [[Int]]) -> [[Int]] {
        let unseen = -1
        let count = edges.count
        var index = [Int](repeating: unseen, count: count)
        var low = [Int](repeating: 0, count: count)
        var onStack = [Bool](repeating: false, count: count)
        var stack: [Int] = []
        var next = 0
        var found: [[Int]] = []
        for start in 0..<count where index[start] == unseen {
            var work: [(node: Int, edge: Int)] = [(start, 0)]
            index[start] = next
            low[start] = next
            next += 1
            stack.append(start)
            onStack[start] = true
            while let (node, edge) = work.last {
                if edge < edges[node].count {
                    let to = edges[node][edge]
                    work[work.count - 1].edge += 1
                    if index[to] == unseen {
                        index[to] = next
                        low[to] = next
                        next += 1
                        stack.append(to)
                        onStack[to] = true
                        work.append((to, 0))
                    } else if onStack[to] {
                        low[node] = min(low[node], index[to])
                    }
                    continue
                }
                work.removeLast()
                if let parent = work.last?.node {
                    low[parent] = min(low[parent], low[node])
                }
                if low[node] == index[node] {
                    var component: [Int] = []
                    while let member = stack.popLast() {
                        onStack[member] = false
                        component.append(member)
                        if member == node { break }
                    }
                    if component.count > 1 {
                        found.append(component.sorted())
                    }
                }
            }
        }
        return found.sorted { $0.lexicographicallyPrecedes($1) }
    }
}
