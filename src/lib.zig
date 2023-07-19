const std = @import("std");
const builtin = @import("builtin");
const Thread = std.Thread;
const Atomic = std.atomic.Atomic;
const Mutex = Thread.Mutex;
const testing = std.testing;

pub const RLock = struct {
    mutex: Mutex,
    locking_thread: Atomic(Thread.Id),
    _count: u16,

    const Self = @This();
    fn init() Self {
        return Self{
            .locking_thread = Atomic(Thread.Id).init(0), // 0 means it's not locked.
            .mutex = .{},
            ._count = 0,
        };
    }

    inline fn tryLock(self: *@This()) bool {
        const current_id = Thread.getCurrentId();
        if (self.locking_thread.load(.Unordered) == current_id and current_id != 0) {
            self._count += 1;
            return true;
        }

        const locking = self.mutex.tryLock();
        if (locking) {
            self.locking_thread.store(Thread.getCurrentId(), .Unordered);
            self._count = 1;
        }
        return locking;
    }

    inline fn lock(self: *@This()) void {
        const current_id = Thread.getCurrentId();
        if (self.locking_thread.load(.Unordered) == current_id and current_id != 0) {
            self._count += 1;
            return;
        }
        self.mutex.lock();
        self.locking_thread.store(current_id, .Unordered);
        self._count = 1;
    }

    inline fn unlock(self: *@This()) void {
        std.debug.assert(self.locking_thread.load(.Unordered) == Thread.getCurrentId());
        self._count -= 1;
        if (self._count == 0) {
            self.locking_thread.store(0, .Unordered);
            self.mutex.unlock();
        }
    }
};

// --------------------------------------------------------------------------------
//                                   Testing
// --------------------------------------------------------------------------------

test "RLock - smoke test" {
    var rlock = RLock.init();

    try testing.expect(rlock.tryLock());
    try testing.expect(rlock.tryLock());

    rlock.unlock();
    rlock.unlock();
}

const NonAtomicCounter = struct {
    value: [2]u64 = [_]u64{ 0, 0 },

    fn get(self: NonAtomicCounter) u128 {
        return @as(u128, @bitCast(self.value));
    }

    fn inc(self: *NonAtomicCounter) void {
        for (@as([2]u64, @bitCast(self.get() + 1)), 0..) |v, i| {
            @as(*volatile u64, @ptrCast(&self.value[i])).* = v;
        }
    }
};

test "RLock - many uncontended" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    const num_threads = 4;
    const num_increments = 1000;

    const Runner = struct {
        rlock: RLock = RLock.init(),
        thread: Thread = undefined,
        counter: NonAtomicCounter = .{},

        fn run(self: *@This()) void {
            var i: usize = num_increments;
            while (i > 0) : (i -= 1) {
                self.rlock.lock();
                self.counter.inc();

                self.rlock.lock();
                self.counter.inc();

                self.rlock.unlock();
                self.rlock.unlock();
            }
        }
    };

    var runners = [_]Runner{.{}} ** num_threads;
    for (&runners) |*r| r.thread = try Thread.spawn(.{}, Runner.run, .{r});
    for (runners) |r| r.thread.join();
    for (runners) |r| try testing.expectEqual(r.counter.get(), num_increments * 2);
}

test "RLock - many contended" {
    if (builtin.single_threaded) {
        return error.SkipZigTest;
    }

    const num_threads = 4;
    const num_increments = 1000;

    const Runner = struct {
        rlock: RLock = RLock.init(),
        counter: NonAtomicCounter = .{},

        fn run(self: *@This()) void {
            var i: usize = num_increments;
            while (i > 0) : (i -= 1) {
                if (i % 100 == 0) Thread.yield() catch {};
                self.rlock.lock();
                if (i % 100 == 0) Thread.yield() catch {};
                self.counter.inc();
                if (i % 100 == 0) Thread.yield() catch {};
                self.rlock.lock();
                if (i % 100 == 0) Thread.yield() catch {};
                self.counter.inc();
                if (i % 100 == 0) Thread.yield() catch {};
                self.rlock.unlock();
                if (i % 100 == 0) Thread.yield() catch {};
                self.rlock.unlock();
            }
        }
    };

    var runner = Runner{};

    var threads: [num_threads]Thread = undefined;
    for (&threads) |*t| t.* = try Thread.spawn(.{}, Runner.run, .{&runner});
    for (threads) |t| t.join();

    try testing.expectEqual(runner.counter.get(), num_increments * num_threads * 2);
}
