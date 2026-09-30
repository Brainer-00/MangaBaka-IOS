# Performance Profiling Guide

This guide is a measurement plan, not performance evidence. Record actual
profile-mode results before describing MangaBaka iOS as fast, smooth, or
memory-stable.

## Existing Windows-side harnesses

Run these serially from the repository root:

```powershell
flutter test --no-pub benchmark/library_hot_path_benchmark_test.dart
flutter test --no-pub benchmark/browse_pagination_benchmark_test.dart
```

`library_hot_path_benchmark_test.dart` creates deterministic synthetic Library
sets of 100, 1,000, and 5,000 entries. Each entry has realistic titles and
aliases, genres/tags, state, progress, ratings, content rating, and a cover
URL. It measures operation counts and prints informational timings for:

- database read and mapping;
- filter/sort and tab partitioning;
- three indexed autocomplete queries;
- watch-stream emissions and mapping passes after representative writes.

`browse_pagination_benchmark_test.dart` verifies that 50 pages of 20 entries
append linearly, rather than rebuilding prior page contents.

These are structural measurements. Their timings are machine- and build-mode
dependent, so they are not pass/fail thresholds and are not iPhone results.

Useful Windows-testable checks also include request counts, startup ordering,
controller/listener disposal, repeated route construction, and synthetic
large-Library filter/autocomplete operation counts. There is currently no
`integration_test` target, frame-timing collector, or test-only profiling
route; add one only when it can answer a concrete question that the current
benchmarks cannot.

## Frame timing

Use profile mode on a real device. The preferred sources are:

1. Flutter DevTools Performance view for frame timeline inspection.
2. `SchedulerBinding.addTimingsCallback` only in an isolated profile/test
   harness, if automated collection becomes necessary.
3. Xcode Instruments for native CPU, memory, and launch investigation.

For each measured scenario, record total frames, build and raster duration
p50/p95/p99, frames above 16.7 ms, frames above 33.3 ms, and the worst frame.
These are outputs to compare between runs, not automated gates yet.

## Startup measurement model

Do not combine these into one number:

| Metric | Measurement source |
| --- | --- |
| Native process launch to first Flutter frame | Xcode Instruments / device launch trace |
| Flutter/Dart first-frame work | DevTools timeline in profile mode |
| First frame to Home usable | manual device observation plus network trace |
| Cold launch | clean process, cache state recorded |
| Warm launch | resume/relaunch state recorded |

The startup metadata cache is restored before the first frame so labels and
indexes are available. Its network refresh is scheduled after the first frame.
Home readiness remains network-dependent and must be reported separately.

## iPhone 11 Pro Max profile script

Required environment: macOS, Xcode, current Flutter iOS tooling, a physical
iPhone 11 Pro Max, and a profile build. Windows measurements can support
structural comparisons but are not substitutes for these results.

Before each measured run:

1. Record app build, iOS version, device free storage, network type, and
   whether the launch is cold or warm.
2. Start DevTools Performance and memory views; prepare Xcode Instruments when
   native launch or memory attribution is needed.
3. Use the existing benchmark fixture only for test-side structural work. Do
   not ship a generated 5,000-entry database in the app.

For each scenario, record preparation, action, metrics, suspicious behavior,
and whether it is deterministic or network-dependent:

| Scenario | Action | Capture | Suspicious behavior |
| --- | --- | --- | --- |
| Cold launch | clean install/process start to Home | native launch, first frame, Home usable | blank/stalled launch or delayed controls |
| Warm launch | terminate/relaunch after prior use | same startup metrics | regression versus recorded cold/warm baseline |
| Home | initial load and rail scroll | requests, frames, image activity | simultaneous stalls or repeated reloads |
| Root tabs | switch tabs rapidly for one minute | frame distribution, retained state | scroll/state loss, duplicate requests, rising memory |
| Browse | scroll through many pages | page/request counts, frame timings | jank, duplicate pages, image reloads |
| Live Search | type, delete, and select results | input responsiveness, requests | delayed input or stale results |
| Library | exercise 100/1,000/5,000 entries where feasible | filter/autocomplete work, frames, memory | long filtering pauses or retained growth |
| Series Detail | open/back repeatedly | route count, frames, memory | retained routes, listener/controller growth |
| Blur-heavy | view allowed-but-blurred covers | raster frames, image memory | raster jank or cover reload loops |
| Image-heavy | scroll cover-dense screens | external memory, image cache behavior | monotonic external memory after idle |
| Lifecycle | background/foreground repeatedly | recovery requests, frame timing | duplicate refreshes, broken state, crashes |

## Mixed-use soak

Run for 20–30 minutes with normal network conditions. Cycle through Home
scrolling, rapid root-tab switching, Browse pagination, Search typing/result
opening, Library filtering/search, Series Detail open/back loops, blurred
covers, image-heavy lists, and background/foreground transitions.

Capture memory snapshots at start, about 5 minutes, about 15 minutes, end, and
after a few idle minutes. Record Dart heap, external/native memory, image cache
observations, retained route/widget counts where visible, GC activity, and any
monotonic growth. Do not set acceptable memory values until a baseline exists.

Review network activity, application logs, crash reports, and error surfaces at
the end of every soak.

## Result template

```text
Run metadata
  build / commit:
  device / iOS:
  Flutter mode:
  network:
  cold or warm:

Startup
  native launch -> first frame:
  Flutter first-frame work:
  first frame -> Home usable:
  cold launch:
  warm launch:

Frames
  total:
  >16.7 ms:
  >33.3 ms:
  build p50 / p95 / p99:
  raster p50 / p95 / p99:
  worst frame:

Memory
  start:
  5 min:
  15 min:
  end:
  idle after soak:

Workflows
  Home:
  Browse:
  Search:
  Library 100 / 1,000 / 5,000:
  Series Detail:
  blur-heavy screen:

Observations
  visible jank:
  delayed input:
  image popping/reloads:
  memory growth:
  requests/logs/errors/crashes:
```

The provisional goals remain goals only: a 60 Hz frame budget is 16.7 ms,
search feedback is approximately a 50 ms-class goal, navigation feedback is
approximately a 100 ms-class goal, cold first frame is provisionally <=1.5 s
p95, and warm launch is provisionally <=700 ms. Real device profile data is
required before judging them.
