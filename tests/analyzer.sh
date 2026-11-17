#!/bin/sh
set -eu

analyzer=$1
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM

"$analyzer" examples/demo.csv > "$scratch/report.txt"
diff -u examples/expected-output.txt "$scratch/report.txt"

cat > "$scratch/fifo.csv" <<'CSV'
time_ms,event,lane
10,ENTRY,A
20,ENTRY,A
30,ENTRY,B
40,EXIT,A
50,EXIT,B
60,EXIT,A
CSV
cat > "$scratch/fifo-expected.txt" <<'REPORT'
OK at 40 ms: lane A package exited after 30 ms
OK at 50 ms: lane B package exited after 20 ms
OK at 60 ms: lane A package exited after 40 ms
REPORT
"$analyzer" "$scratch/fifo.csv" > "$scratch/report.txt"
diff -u "$scratch/fifo-expected.txt" "$scratch/report.txt"

printf 'time_ms,event,lane\r\n0,ENTRY,B\r\n999,TICK,\r\n1000,EXIT,B\r\n' > "$scratch/boundary.csv"
printf '%s\n' 'JAM at 1000 ms: lane B package waiting for 1000 ms' > "$scratch/boundary-expected.txt"
"$analyzer" "$scratch/boundary.csv" > "$scratch/report.txt"
diff -u "$scratch/boundary-expected.txt" "$scratch/report.txt"

expect_error() {
    trace=$1
    message=$2
    if "$analyzer" "$trace" > "$scratch/report.txt" 2> "$scratch/error.txt"; then
        printf 'Expected analyzer to reject %s\n' "$trace" >&2
        exit 1
    fi
    grep -F "$message" "$scratch/error.txt" > /dev/null
}

printf 'time_ms,event,lane\n10,ENTRY,A\n20,EXIT,B\n' > "$scratch/wrong-lane.csv"
expect_error "$scratch/wrong-lane.csv" 'EXIT without a matching ENTRY'

printf 'time_ms,event,lane\n10,ENTRY,A\n9,TICK,\n' > "$scratch/backwards.csv"
expect_error "$scratch/backwards.csv" 'timestamps must be chronological'

{
    printf 'time_ms,event,lane\n'
    i=0
    while [ "$i" -lt 17 ]; do
        printf '%s,ENTRY,B\n' "$i"
        i=$((i + 1))
    done
} > "$scratch/overflow.csv"
expect_error "$scratch/overflow.csv" 'lane queue overflow on ENTRY'

printf '%s\n' 'C analyzer tests passed.'
