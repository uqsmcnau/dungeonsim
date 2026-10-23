#!/usr/bin/env bash
# Balance report: plays several whole games at once, headless (see
# tools/balance.gd), and prints what happened in them on average -- the win
# rate, what killed everyone, mid boss parties beaten, silver and gold
# chests, silver shop visits, the gear players got and the levels reached.
# For telling whether a change made the game harder or easier.
#
# Usage, from anywhere: tools/balance.sh [games=12] [first_seed=1] [speed=10]
# Set GODOT to the Godot binary if it isn't on the PATH as `godot`.
set -u
cd "$(dirname "$0")/.."
godot_bin=${GODOT:-godot}
games=${1:-12}
first=${2:-1}
speed=${3:-10}
logs=$(mktemp -d)

for ((s = first; s < first + games; s++)); do
	"$godot_bin" --headless --path . --fixed-fps 60 --time-scale "$speed" -s tools/balance.gd -- --seed="$s" >"$logs/$s.log" 2>&1 &
done
wait

cat "$logs"/*.log | grep "^BALANCE " >"$logs/all.txt"
"$godot_bin" --headless --path . -s tools/balance.gd -- --summarise="$logs/all.txt" 2>&1 | grep -v "^Godot Engine"
rm -rf "$logs"
