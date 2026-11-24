public func boot(_ ids: [UInt32], until: UInt64) -> Int {
    var tasks = Tasks()
    var timers = Timers()
    for id in ids {
        tasks.spawn(id, timers: &timers)
    }
    var awake = 0
    for now in 0..<until {
        timers.fire(now, tasks: &tasks)
        awake = tasks.runnable
    }
    return awake
}
