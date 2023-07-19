const std = @import("std");
const Thread = std.Thread;

const RLock = @import("RLock").RLock;

var counter: usize = 0;
var rlock = RLock.init();

pub fn main() !void {
    var threads: [100]std.Thread = undefined;

    for (&threads) |*handle| {
        handle.* = try std.Thread.spawn(.{}, struct {
            fn thread_fn() !void {
                for (0..100) |_| {
                    rlock.lock();
                    defer rlock.unlock();
                    counter += 1;

                    Thread.yield() catch {};

                    rlock.lock();
                    defer rlock.unlock();
                    counter += 1;
                }
            }
        }.thread_fn, .{});
    }

    for (threads) |handle| {
        handle.join();
    }

    std.debug.assert(counter == 20000);
    std.debug.print("counter => {d}\n", .{counter});
}
