#!/bin/bash
# Orchestrate benchmark measurements: cold launch, live-reload, and rendering.
# Parses marker lines from stderr and compares measured vs budgeted latency.
# Exits 0 regardless of budget status; CI records the numbers as an informational
# trend, not a gate.

set -e

FIXTURE="${1:-.build/bench/fixture.md}"
BINARY="${2:-.build/arm64-apple-macosx/release/Folium}"

if [[ ! -f "$FIXTURE" ]]; then
    echo "Error: fixture not found at $FIXTURE"
    exit 1
fi

if [[ ! -f "$BINARY" ]]; then
    echo "Error: binary not found at $BINARY"
    exit 1
fi

echo "Benchmark Results"
echo "================="
echo ""

# Capture launch timing. Run the app with FOLIUM_BENCH set, measuring time
# from process start to first-paint marker.
# The app launches, opens the fixture, renders it, and emits markers to stderr.
echo "Running cold-launch benchmark..."

TEMP_OUTPUT=$(mktemp)
trap "rm -f $TEMP_OUTPUT; killall -q Folium 2>/dev/null || true" EXIT

# Run the app and capture all output to a temp file
FOLIUM_BENCH=1 "$BINARY" "$FIXTURE" > "$TEMP_OUTPUT" 2>&1 &
BENCH_PID=$!

# Wait up to 8 seconds for markers to appear
MARKERS_SEEN=0
for i in {1..80}; do
    if grep -q "^FOLIUM_BENCH" "$TEMP_OUTPUT" 2>/dev/null; then
        MARKERS_SEEN=1
        sleep 1  # Give a bit more time for all markers to be written
        break
    fi
    sleep 0.1
done

# Kill the app
kill -9 $BENCH_PID 2>/dev/null || true
wait $BENCH_PID 2>/dev/null || true
killall -q Folium 2>/dev/null || true

# Read the output
LAUNCH_OUTPUT=$(grep "^FOLIUM_BENCH" "$TEMP_OUTPUT" 2>/dev/null || true)

# Parse markers from output. Format is "FOLIUM_BENCH <event> <elapsed-seconds>".
LAUNCH_TIME=""
RELOAD_TIME=""
RENDER_TIME=""

while IFS=' ' read -r marker event time; do
    if [[ "$marker" == "FOLIUM_BENCH" ]]; then
        case "$event" in
            launch)
                # Marker at app startup.
                LAUNCH_START=$(echo "$time" | sed 's/[.]//' | cut -c1-3)
                ;;
            first-paint)
                # First render complete.
                LAUNCH_TIME=$time
                ;;
            render-start)
                RENDER_START=$time
                ;;
            render-end)
                RENDER_TIME=$(echo "$time - $RENDER_START" | bc)
                ;;
            reload-paint)
                RELOAD_TIME=$time
                ;;
        esac
    fi
done <<< "$LAUNCH_OUTPUT"

# Report results. Print measured vs budget for each moment.
echo ""
echo "Measurements"
echo "============"
echo ""

# Cold launch → first document painted
if [[ -n "$LAUNCH_TIME" ]]; then
    LAUNCH_MS=$(echo "$LAUNCH_TIME * 1000" | bc | xargs printf "%.0f")
    echo "$(python3 -c "
import sys
sys.path.insert(0, 'Sources')
# Can't easily call Swift functions from shell, so format inline.
# Budget is 500 ms
budget = 500
measured = $LAUNCH_MS
status = '✓' if measured <= budget else '✗'
suffix = f' (over by {measured - budget} ms)' if measured > budget else ''
name = 'Cold launch → first document painted'
dots = max(1, 60 - len(name) - len(str(measured)))
print(f'  {name}{"." * dots} {measured} ms  {status}{suffix}')
")"
else
    echo "  Cold launch → first document painted....... not measured (app did not emit first-paint marker)"
fi

# Live-reload: file written → repainted
# This requires the app to be running and watching the fixture, then writing it.
# Since we can't do this with just the shell, we report it as unmeasured.
echo "  Live-reload: file written → repainted........ not measured (requires driving running app)"

# Markdown → HTML render (fixture, no budget)
if [[ -n "$RENDER_TIME" ]]; then
    RENDER_MS=$(echo "$RENDER_TIME * 1000" | bc | xargs printf "%.0f")
    echo "  Markdown → HTML render (fixture)........... $RENDER_MS ms  –"
else
    echo "  Markdown → HTML render (fixture)........... not measured (renderer did not emit timing)"
fi

# Unmeasured moments per spec
echo "  Warm open (app already running) → painted.. not measured (requires driving running app's UI)"
echo "  Tab switch.............................. not measured (requires multiple tabs, UI driving)"
echo "  Scrolling / dropped frames............... not measured (scope of issue)"

echo ""
echo "Notes"
echo "====="
echo "- Warm open and tab switch require driving an already-running app, which"
echo "  a shell script cannot do honestly (timing measurements from the shell"
echo "  would include shell overhead, not measure the app's actual latency)."
echo "- Scrolling and dropped-frames measurement is out of scope for this fixture."
echo "- Live-reload timing requires file system coordination that shell scripts"
echo "  cannot reliably perform."
echo "- Measured moments are from FOLIUM_BENCH markers in stderr; unmeasured"
echo "  moments would need different instrumentation (UI automation, frame capture)."
echo ""

# Always exit 0. CI records these numbers as an informational trend, not a gate.
exit 0
