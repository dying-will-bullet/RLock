# RLock

[![CI](https://github.com/dying-will-bullet/RLock/actions/workflows/ci.yaml/badge.svg)](https://github.com/dying-will-bullet/RLock/actions/workflows/ci.yaml)
![](https://img.shields.io/badge/language-zig-%23ec915c)

A reentrant lock is a synchronization primitive that may be acquired multiple times by the same thread.
Internally, it uses the concepts of "owning thread" and "recursion level" in addition to the locked/unlocked state used by primitive locks.
In the locked state, some thread owns the lock; in the unlocked state, no thread owns it.

## Example

```zig
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
```

## License

MIT
