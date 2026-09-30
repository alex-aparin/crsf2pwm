#!/usr/bin/env bash
# Compile a Quartus revision and print what matters: errors, every warning
# code with its count, resources, timing.
#
#   tools/build.sh                the board revision, crsf2pwm_c4
#   tools/build.sh clock_probe    the bring-up probe
#   tools/build.sh crsf2pwm       the MAX II revision (does not fit yet)
#
# Full log: quartus/output_files/<revision>.build.log

set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
rev=${1:-crsf2pwm_c4}

. "$here/tools/quartus-env.sh"
command -v quartus_sh >/dev/null || exit 1

cd "$here/quartus" || exit 1
[ -f "$rev.qsf" ] || { echo "build: no revision $rev (quartus/$rev.qsf)"; exit 1; }
mkdir -p output_files
log=output_files/$rev.build.log

echo "build: $rev"
if quartus_sh --flow compile crsf2pwm -c "$rev" >"$log" 2>&1; then
  ok=1
else
  ok=0
fi

# Errors and critical warnings, verbatim.
grep -E '^(Error|Critical Warning)' "$log" | grep -vE '\((15714|169177)\)' || true

# Warnings grouped by code: the list to read after every change.
# 18236 is "set NUM_PARALLEL_PROCESSORS", 292013 is the LogicLock licence
# note, 332153 says the family has no jitter analysis: noise, not design.
echo "warnings:"
grep -oE '^Warning \([0-9]+\): .*' "$log" \
  | grep -vE '\((18236|292013|332153)\)' \
  | sed -E 's/^Warning \(([0-9]+)\): (.{0,90}).*/  \1  \2/' \
  | sort | uniq -c | sort -rn | sed 's/^ *\([0-9]*\) /  x\1 /' || true

if [ -f "output_files/$rev.fit.summary" ]; then
  grep -E 'Device|Total logic elements|Total registers|Total pins' "output_files/$rev.fit.summary" | sed 's/^/  /'
fi
if [ -f "output_files/$rev.sta.rpt" ]; then
  grep -m1 -E 'Worst-case setup slack' "output_files/$rev.sta.rpt" | sed 's/^ *Info ([0-9]*): /  /'
fi

if [ $ok = 1 ]; then
  for f in "output_files/$rev.sof" "output_files/$rev.pof"; do
    [ -f "$f" ] && echo "build ok: quartus/$f"
  done
  exit 0
else
  echo "BUILD FAILED, see quartus/$log"
  exit 1
fi
