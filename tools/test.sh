#!/usr/bin/env bash
# Runs the whole GUT suite in several Godot processes at once -- the test
# files shared out between them, about the same number of tests each -- and
# sums up. Same tests as the plain runner (godot ... -s
# addons/gut/gut_cmdln.gd), a fraction of the time: almost all of it goes on
# building a fresh game for each test, and the files don't share anything.
# Prints every failure in full; exits 1 if anything failed or a process
# didn't finish.
#
# Usage, from anywhere: tools/test.sh [jobs=number of cores, at most 8]
# Set GODOT to the Godot binary if it isn't on the PATH as `godot`.
set -u
cd "$(dirname "$0")/.."
godot_bin=${GODOT:-godot}
cores=$(nproc 2>/dev/null || echo 4)
jobs=${1:-$((cores < 8 ? cores : 8))}
logs=$(mktemp -d)
start=$(date +%s)

# Share the files out, biggest first, each to whichever job has the fewest
# tests so far.
declare -a load lists
for ((j = 0; j < jobs; j++)); do
	load[j]=0
	lists[j]=""
done
while read -r count file; do
	least=0
	for ((j = 1; j < jobs; j++)); do
		if ((load[j] < load[least])); then least=$j; fi
	done
	load[least]=$((load[least] + count))
	lists[least]="${lists[least]:+${lists[least]},}res://$file"
done < <(for f in tests/unit/test_*.gd; do echo "$(grep -c '^func test_' "$f") $f"; done | sort -rn)

for ((j = 0; j < jobs; j++)); do
	[ -z "${lists[j]}" ] && continue
	"$godot_bin" --headless --path . -s addons/gut/gut_cmdln.gd -gconfig= -gexit -glog=1 -gdisable_colors \
		-gtest="${lists[j]}" >"$logs/$j.log" 2>&1 &
done
wait

passed=0
failed=0
broken=0
for ((j = 0; j < jobs; j++)); do
	log="$logs/$j.log"
	[ -f "$log" ] || continue
	if ! grep -q "^Totals" "$log"; then
		echo "Job $j never finished:"
		tail -20 "$log"
		broken=1
		continue
	fi
	passed=$((passed + $(grep -E "^Passing Tests" "$log" | grep -oE "[0-9]+" || echo 0)))
	these=$(grep -E "^Failing Tests" "$log" | grep -oE "[0-9]+" || echo 0)
	failed=$((failed + these))
	if ((these > 0)); then
		sed -n '/^= Run Summary/,$p' "$log" | grep -vE "^(Totals|---|Scripts|Tests|Passing|Failing|Asserts|Time|Deprecated|Pending|Risky|=)" | grep -v "^\s*$"
	fi
	if grep -q "SCRIPT ERROR" "$log"; then
		grep -A3 "SCRIPT ERROR" "$log" | head -20
	fi
done
rm -rf "$logs"
echo "Tests: $passed passed, $failed failed, in $(($(date +%s) - start))s over $jobs jobs."
if ((failed > 0 || broken > 0)); then
	exit 1
fi
