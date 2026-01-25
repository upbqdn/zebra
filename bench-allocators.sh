echo Thanks to these instructions: https://github.com/ZcashFoundation/zebra/blob/main/book/src/dev/profiling-and-benchmarking.md

# CPU type on linuxy
CPUTYPE=`grep "model name" /proc/cpuinfo 2>/dev/null | uniq | cut -d':' -f2-`

if [ "x${CPUTYPE}" = "x" ] ; then
    # CPU type on macos
    CPUTYPE=`sysctl -n machdep.cpu.brand_string 2>/dev/null`
fi

CPUTYPE="${CPUTYPE//[^[:alnum:]]/}"

OSTYPESTR="${OSTYPE//[^[:alnum:]]/}"

ARGS=$*
ARGSSTR="${ARGS//[^[:alnum:]]/}"

BNAME="zebra"
FNAME="${BNAME}.result.${CPUTYPE}.${OSTYPESTR}.${ARGSSTR}.txt"
RESF="tmp/${FNAME}"

echo "# Saving result into \"${RESF}\""

rm -f $RESF
mkdir -p tmp

echo "# git log -1 | head -1" 2>&1 | tee -a $RESF
git log -1 | head -1 2>&1 | tee -a $RESF
echo 2>&1 | tee -a $RESF

echo "( [ -z \"\$(git status --porcelain)\" ] && echo \"Clean\" || echo \"Uncommitted changes\" )" 2>&1 | tee -a $RESF
( [ -z "$(git status --porcelain)" ] && echo "Clean" || echo "Uncommitted changes" ) 2>&1 | tee -a $RESF
echo 2>&1 | tee -a $RESF

echo CPU type: 2>&1 | tee -a $RESF
echo $CPUTYPE 2>&1 | tee -a $RESF
echo 2>&1 | tee -a $RESF

echo OS type: 2>&1 | tee -a $RESF
echo $OSTYPE 2>&1 | tee -a $RESF
echo 2>&1 | tee -a $RESF

if [ "x${OSTYPE}" = "xmsys" ]; then
        # no jemalloc or snmalloc on windows
        # ALLOCATORS="(mi|rp|s)malloc"
        ALLOCATORS="(mi|rp|s)malloc" # convert from regex to shell list
else
        # xxx for real comparison ALLOCATORS="(je|sn|mi|rp|s)malloc"
        ALLOCATORS="smalloc" # for testing this benchmarking script
fi

cargo build --release 2>&1 | tee tmp/cargo.build.log.txt &&

./target/release/zebrad --config zebrad-synced.toml 2>&1 | tee tmp/zebrad-synced.log.txt &
SYNCED_ZEBRAD_PID=$!

trap "kill $SYNCED_ZEBRAD_PID" EXIT

for ALLOCATOR in ${ALLOCATORS}; do
    cargo build --release --features=$ALLOCATOR &&
    ( time ./target/release/zebrad --config zebrad-isolated.toml ) 2>&1 | tee ${RESF}
done

echo "# Results are in \"${RESF}\" ."
