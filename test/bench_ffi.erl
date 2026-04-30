-module(bench_ffi).
-export([monotonic_ns/0]).

%% Returns a monotonic timestamp in nanoseconds. Suitable for measuring
%% elapsed time inside the benchmark harness; the absolute value has no
%% meaning, only differences do.
monotonic_ns() -> erlang:monotonic_time(nanosecond).
