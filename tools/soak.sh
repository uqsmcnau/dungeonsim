#!/usr/bin/env bash
# Soak test: plays several whole games at once, headless, each watched by
# tools/soak.gd (frozen leaders, icons adrift from their cells, stale map
# entries, fog lit with nobody near) -- and flags any script errors too.
# Exits 1 if anything turned up; each game replays exactly from its seed and
# speed:
#   godot --headless --path . --fixed-fps 60 --time-scale S -s tools/soak.gd -- --seed=N
#
# Usage, from anywhere: tools/soak.sh [games=8] [first_seed=1] [seconds=600] [speed=1]
# `speed` is the toolbar's game speed (1, 2, 5 or 10): x10 gets through a
# game in about a tenth of the frames, which is what CI runs on every push.
# Set GODOT to the Godot binary if it isn't on the PATH as `godot`.
set -u
cd "$(dirname "$0")/.."
godot_bin=${GODOT:-godot}
games=${1:-8}
first=${2:-1}
seconds=${3:-600}
speed=${4:-1}
logs=$(mktemp -d)

for ((s = first; s < first + games; s++)); do
	"$godot_bin" --headless --path . --fixed-fps 60 --time-scale "$speed" -s tools/soak.gd -- --seed="$s" --seconds="$seconds" >"$logs/$s.log" 2>&1 &
done
wait

failed=0
loops=0
for ((s = first; s < first + games; s++)); do
	log="$logs/$s.log"
	if ! grep -q "^SOAK seed=$s " "$log"; then
		echo "SOAK seed=$s never finished:"
		tail -20 "$log"
		failed=1
		continue
	fi
	grep -E "^(SOAK|PROBLEM|LOOP|  [A-Z][a-z]+:|    t=)" "$log"
	loops=$((loops + $(grep -c "^LOOP" "$log")))
	if grep -q "^PROBLEM" "$log"; then
		failed=1
	fi
	if grep -q "SCRIPT ERROR" "$log"; then
		echo "SCRIPT ERROR in seed $s:"
		grep -A3 "SCRIPT ERROR" "$log" | head -20
		failed=1
	fi
done
rm -rf "$logs"
if [ "$failed" -eq 0 ]; then
	echo "Soak: $games games, no problems$([ "$loops" -gt 0 ] && echo " ($loops AI loops noted -- see LOOP above)")."
fi
exit "$failed"
