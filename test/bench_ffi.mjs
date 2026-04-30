// Benchmark FFI helpers for the JavaScript target.

// Returns a monotonic timestamp in nanoseconds. `performance.now()` is
// available in Node and modern browsers, returns sub-millisecond
// resolution as a float, and is monotonic across the lifetime of the
// process. Only differences are meaningful.
export function monotonic_ns() {
  return Math.floor(performance.now() * 1_000_000);
}
