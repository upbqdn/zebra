#!/bin/bash
set -e

echo "Thanks to these instructions: https://github.com/ZcashFoundation/zebra/blob/main/book/src/dev/profiling-and-benchmarking.md"

# --- Cleanup handling ---
cleanup() {
    if pgrep -f "zebrad.*zebrad-synced.toml" >/dev/null 2>&1; then
        echo "Stopping synced zebrad..."
        pkill -f "zebrad.*zebrad-synced.toml" 2>/dev/null
        # Wait for process to actually die (up to 10 seconds)
        for i in {1..10}; do
            pgrep -f "zebrad.*zebrad-synced.toml" >/dev/null 2>&1 || break
            sleep 1
        done
    fi
}

trap cleanup EXIT INT TERM

# --- System info ---
CPUTYPE=$(grep "model name" /proc/cpuinfo 2>/dev/null | uniq | cut -d':' -f2-)
if [ -z "$CPUTYPE" ]; then
    CPUTYPE=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
fi
CPUTYPE="${CPUTYPE//[^[:alnum:]]/}"

OSTYPESTR="${OSTYPE//[^[:alnum:]]/}"
ARGSSTR="${*//[^[:alnum:]]/}"

# --- Output file setup ---
BNAME="zebra"
FNAME="${BNAME}.result.${CPUTYPE}.${OSTYPESTR}.${ARGSSTR}.txt"
RESF="tmp/${FNAME}"

echo "# Saving result into \"${RESF}\""

mkdir -p tmp
rm -f "$RESF"

# --- Log git and system info ---
{
    echo "# git log -1 | head -1"
    git log -1 | head -1
    echo
    echo "# git status"
    if [ -z "$(git status --porcelain)" ]; then
        echo "Clean"
    else
        echo "Uncommitted changes"
    fi
    echo
    echo "CPU type:"
    echo "$CPUTYPE"
    echo
    echo "OS type:"
    echo "$OSTYPE"
    echo
} 2>&1 | tee -a "$RESF"

# --- Build and start synced zebrad ---
echo "Building zebrad..."
cargo build --release 2>&1 | tee tmp/cargo.build.log.txt

echo "Starting synced zebrad..."
./target/release/zebrad --config zebrad-synced.toml >tmp/zebrad-synced.log.txt 2>&1 &

# Verify it started
sleep 2
if ! pgrep -f "zebrad.*zebrad-synced.toml" >/dev/null 2>&1; then
    echo "ERROR: Failed to start synced zebrad (port 8233 already in use?)"
    exit 1
fi

# Wait for it to be ready
echo "Waiting for synced zebrad to listen on port 8233..."
timeout=60
check_port() {
    if command -v ss >/dev/null 2>&1; then
        ss -tln | grep -q ':8233 '
    else
        lsof -iTCP:8233 -sTCP:LISTEN >/dev/null 2>&1
    fi
}
while ! check_port; do
    sleep 1
    timeout=$((timeout - 1))
    if [ "$timeout" -le 0 ]; then
        echo "ERROR: Timed out waiting for zebrad to listen on port 8233"
        exit 1
    fi
    if ! pgrep -f "zebrad.*zebrad-synced.toml" >/dev/null 2>&1; then
        echo "ERROR: Synced zebrad died unexpectedly"
        exit 1
    fi
done
echo "Synced zebrad is ready."

# --- Benchmark each allocator ---
for ALLOCATOR in default jemalloc mimalloc rpmalloc smalloc snmalloc; do
    echo
    echo "=== Benchmarking allocator: $ALLOCATOR ===" | tee -a "$RESF"
    if [ "$ALLOCATOR" = "default" ]; then
        cargo build --release >"tmp/cargo-build-${ALLOCATOR}.log" 2>&1
    else
        cargo build --release --features="$ALLOCATOR" >"tmp/cargo-build-${ALLOCATOR}.log" 2>&1
    fi
    { time ./target/release/zebrad --config zebrad-isolated.toml >"tmp/zebrad-${ALLOCATOR}.log" 2>&1; } 2>&1 | tee -a "$RESF"
done

echo
echo "# Results are in \"${RESF}\""
