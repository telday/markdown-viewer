#!/bin/bash
# Orchestrates the latency-budget measurements: launches the app with the
# fixture, waits for its markers, writes real new content to trigger a
# live-reload, and prints measured vs budgeted latency. Exits 0 regardless;
# CI records the numbers as an informational trend, not a gate (see issue #21
# and CONTEXT.md's perceived-latency priority).
#
# BenchMarker inside the app emits absolute wall-clock timestamps (seconds
# since the Unix epoch, gated on FOLIUM_BENCH) rather than elapsed durations.
# Cold launch has to be timed from OUTSIDE the process: dyld and AppKit
# start-up happen before any of our Swift code runs, so an in-process
# baseline can never see them. This script takes its own wall-clock reading
# immediately before it execs the app and subtracts that from the
# `first-paint` marker instead.
set -euo pipefail

FIXTURE="${1:-.build/bench/fixture.md}"
BINARY="${2:-.build/arm64-apple-macosx/release/Folium}"

if [[ ! -f "$FIXTURE" ]]; then
    echo "Error: fixture not found at $FIXTURE" >&2
    exit 1
fi
if [[ ! -x "$BINARY" ]]; then
    echo "Error: binary not found at $BINARY" >&2
    exit 1
fi

MARKERS=$(mktemp)
APP_PID=""
cleanup() {
    [[ -n "$APP_PID" ]] && kill -9 "$APP_PID" 2>/dev/null || true
    rm -f "$MARKERS"
}
trap cleanup EXIT

# Same clock `BenchMarker` uses (seconds since the Unix epoch, microsecond
# precision) so a reading taken here and a marker's timestamp can be
# subtracted directly, even though they come from different processes.
wall_clock() {
    python3 -c 'import time; print(f"{time.time():.6f}")'
}

# Polls $MARKERS for a line starting "FOLIUM_BENCH <event> ", up to
# $2 tenths of a second. FileWatcher's coalescing window and WebKit's own
# scheduling mean a marker can arrive anywhere from a few milliseconds to a
# couple of seconds after the thing that triggers it, so this is a wait loop
# rather than a fixed sleep.
wait_for_marker() {
    local event="$1" timeout_tenths="$2"
    for ((i = 0; i < timeout_tenths; i++)); do
        if grep -q "^FOLIUM_BENCH ${event} " "$MARKERS" 2>/dev/null; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

# Prints the timestamp field of a marker's first occurrence. First rather
# than last: an event can legitimately repeat (rendering happens once for
# the initial open and again for the live-reload probe below), and the first
# occurrence is always the one this script is asking about.
marker_timestamp() {
    grep -m1 "^FOLIUM_BENCH $1 " "$MARKERS" | awk '{print $3}'
}

# $1 - $2, in whole milliseconds. Both are wall-clock seconds since the Unix
# epoch. Kept as plain arithmetic, not policy — see BenchBudget.swift for the
# budget comparison and report formatting this script hands the result to.
elapsed_ms() {
    python3 -c "print(round(($1 - $2) * 1000))"
}

# Mirrors BenchBudget.reportLine's format so this script's output reads the
# same way the (unit-tested) Swift type would render it. A shell script
# can't call into the app's own Swift code without a second build product
# (see the PR description for why that trade-off wasn't taken), so the budget
# numbers below are a second copy of BenchBudget.budgets — keep them in sync.
report_line() {
    local name="$1" measured_ms="$2" budget_ms="$3"
    if [[ -z "$measured_ms" ]]; then
        local reason="$4"
        local dots=$((60 - ${#name} - 12))  # "not measured" is 12 characters
        [[ $dots -lt 1 ]] && dots=1
        printf '  %s%s not measured (%s)\n' "$name" "$(printf '.%.0s' $(seq 1 "$dots"))" "$reason"
        return
    fi
    local dots=$((60 - ${#name} - ${#measured_ms}))
    [[ $dots -lt 1 ]] && dots=1
    local dotted
    dotted=$(printf '.%.0s' $(seq 1 "$dots"))
    if [[ -z "$budget_ms" ]]; then
        printf '  %s%s %s ms  –\n' "$name" "$dotted" "$measured_ms"
    elif [[ "$measured_ms" -le "$budget_ms" ]]; then
        printf '  %s%s %s ms  \xE2\x9C\x93\n' "$name" "$dotted" "$measured_ms"
    else
        printf '  %s%s %s ms  \xE2\x9C\x97 (over by %s ms)\n' \
            "$name" "$dotted" "$measured_ms" "$((measured_ms - budget_ms))"
    fi
}

echo "Benchmark Results"
echo "================="
echo ""

# Cold launch. FOLIUM_BENCH_OPEN tells FoliumAppDelegate to open the fixture
# as soon as AppKit finishes launching — see that file for why a plain
# command-line argument isn't enough to make a SwiftUI DocumentGroup app open
# a document.
LAUNCH_T0=$(wall_clock)
FOLIUM_BENCH=1 FOLIUM_BENCH_OPEN="$FIXTURE" "$BINARY" 2>"$MARKERS" &
APP_PID=$!

COLD_LAUNCH_MS=""
if wait_for_marker "first-paint" 100; then
    COLD_LAUNCH_MS=$(elapsed_ms "$(marker_timestamp "first-paint")" "$LAUNCH_T0")
fi

# Live-reload. `LiveDocument` deliberately treats a rewrite with unchanged
# rendered output as a no-op — `touch`, or a save of identical bytes, must
# not repaint — so the probe below has to change the document's actual
# content, not just its mtime, or `reload-paint` will never fire.
RELOAD_MS=""
if [[ -n "$COLD_LAUNCH_MS" ]]; then
    printf '\n<!-- bench live-reload probe -->\n' >> "$FIXTURE"
    RELOAD_T0=$(wall_clock)
    if wait_for_marker "reload-paint" 50; then
        RELOAD_MS=$(elapsed_ms "$(marker_timestamp "reload-paint")" "$RELOAD_T0")
    fi
fi

RENDER_MS=""
RENDER_START=$(marker_timestamp "render-start" || true)
RENDER_END=$(marker_timestamp "render-end" || true)
if [[ -n "$RENDER_START" && -n "$RENDER_END" ]]; then
    RENDER_MS=$(elapsed_ms "$RENDER_END" "$RENDER_START")
fi

kill -9 "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true
APP_PID=""

echo "Measurements"
echo "============"
echo ""

if [[ -n "$COLD_LAUNCH_MS" ]]; then
    report_line "Cold launch → first document painted" "$COLD_LAUNCH_MS" 500
else
    report_line "Cold launch → first document painted" "" "" "app did not emit a first-paint marker"
fi

if [[ -n "$RELOAD_MS" ]]; then
    report_line "Live-reload: file written → repainted" "$RELOAD_MS" 100
else
    report_line "Live-reload: file written → repainted" "" "" "app did not emit a reload-paint marker"
fi

if [[ -n "$RENDER_MS" ]]; then
    report_line "Markdown → HTML render (fixture)" "$RENDER_MS" ""
else
    report_line "Markdown → HTML render (fixture)" "" "" "renderer did not emit timing"
fi

report_line "Warm open (app already running) → painted" "" "" "requires driving an already-running app's UI"
report_line "Tab switch" "" "" "requires driving an already-running app's UI"
report_line "Scrolling / dropped frames" "" "" "out of scope for this fixture"

echo ""
echo "Notes"
echo "====="
echo "- Cold launch is timed from this script's own wall-clock reading, taken"
echo "  immediately before exec, to the app's first-paint marker — the only"
echo "  baseline that includes process spawn, dyld, and AppKit start-up."
echo "- Live-reload appends a comment to the fixture (a no-op rewrite would"
echo "  never repaint, by design) and times from that write to reload-paint."
echo "- Warm open and tab switch need an already-running app's UI driven from"
echo "  outside, which a shell script cannot do honestly."
echo "- Scrolling / dropped frames is out of scope for this fixture."
echo ""

# Always exit 0. CI records these numbers as an informational trend, not a
# gate — see CONTEXT.md.
exit 0
