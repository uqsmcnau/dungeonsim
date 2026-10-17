# DungeonSim

A Godot 4.7 (GDScript) spectator simulation: 12 autonomous, AI-controlled
characters explore a procedurally generated maze, gain RPG levels through
encounters, form parties, fight monsters and each other, and race for a
boss room at the center. There is no player input during a run — everything
is driven by each `NpcAgent`'s own decision-making in `_process`.

## Running it

Open `project.godot` in the Godot 4.7 editor and run `Main.tscn` (F5), or
headless for a smoke test:

```
godot --headless --path . scenes/Main.tscn --fixed-fps 60 --quit-after 3600
```

`--fixed-fps 60` matters — without it, frame timing is wall-clock-driven and
unreliable for anything checking tween/timer-based state.

After adding a **new** `class_name` declaration, rebuild the global class
cache once before anything can reference it:

```
godot --headless --editor --path . --quit
```

## Running tests

The test suite is [GUT](https://github.com/bitwes/Gut) 9.7.1, vendored into
`addons/gut` (not a submodule — just vendored files, MIT licensed). Tests
live in `tests/unit/`, one file per concern.

```
godot --headless --path . -s addons/gut/gut_cmdln.gd
```

`.gutconfig.json` in the project root already points the runner at
`tests/unit`, so no extra flags are needed. Exits 0 on success, 1 if any
test fails — safe to gate CI on (see `.github/workflows/tests.yml`).

Most tests instantiate things directly (`NpcStats.new()`, a bare
`MazeGenerator`, a single `NPC_SCENE`/`Enemy.tscn` instance) rather than the
full `Main` scene, which keeps the whole suite under 2 seconds. Only reach
for `load("res://scenes/Main.tscn").instantiate()` when a test actually
needs the generated maze or the full NPC/enemy roster.

## Architecture conventions worth knowing before touching combat/party code

- **Leader/follower pairs, twice.** Both player parties (`NpcAgent.party`)
  and enemy packs (`EnemyAgent.pack`) use the same pattern: one leader makes
  decisions (explore, fight, wander) and runs its own `_process`/think-loop;
  followers just tag along visually (`_follow_to` / `_follow_pack_move`) and
  join combat when the leader does. If a leader dies, a follower is
  promoted automatically (`_promote_next_party_leader` /
  `_promote_next_pack_leader`) — this is load-bearing: without it, the
  survivors would freeze forever, since only leaders ever act.

- **Two different "who represents this cell" dicts.** `game_manager.gd`
  owns `player_map` (cell → party leader) and `enemy_map` (cell → pack
  leader), both shared by reference into every `NpcAgent`/`EnemyAgent`. A
  character is *never* independently discoverable through these dicts
  unless it's currently a leader — followers simply aren't in them.

- **Combat identifies sides by party array reference, not by cell.**
  `_run_group_pvp_turn`/`_run_group_combat_turn` re-derive "who's currently
  driving each side" every turn (so a mid-fight leader death hands off
  cleanly), but PvP specifically keys off `party`/`opponent.party` array
  references rather than cell coordinates. Two parties can legitimately
  occupy the same cell (one found the other already standing on its own
  square), and a cell-keyed lookup collapses both sides into the same dict
  entry when that happens — this was a real, shipped bug (both sides became
  the same object, freezing the fight with no progress) before it was
  caught by `test_pvp_does_not_freeze_when_both_sides_share_a_cell`. If you
  add a new multi-character interaction keyed by cell, ask whether the two
  sides can ever coincide on one cell before assuming the lookup is unique.

- **`_die()` clears its own `in_pvp_combat`/`in_combat`-adjacent state
  directly**, rather than relying on a cleanup pass that walks the party
  array afterward — `party.erase(self)` mutates that array in place, so a
  cleanup step running after the erase can no longer find the member it
  needs to unlock.

- **`NpcAgent`s are never freed.** `_die()` sets `dead = true` and
  `visible = false` but the node stays in the tree forever (so signals/HUD
  rows keep working). `is_instance_valid()` on an `NpcAgent` is therefore
  always true — check `.dead`, not instance validity. `EnemyAgent` and
  `ChestAgent` *are* `queue_free()`'d on defeat/collection, so
  `is_instance_valid()` matters there.

- **"Safe rooms" = `game_manager.restricted_cells`**, exposed to each
  `NpcAgent` as `safe_cells`. Covers start zones, shops, mini boss rooms,
  and the boss room — monsters never spawn there, and PvP can't be
  initiated there either. If a feature needs "is this a peaceful zone"
  logic, this is almost certainly the dict to check rather than inventing a
  parallel concept.

- **Dictionaries as typed lookups.** `enemies[cell]`/`players[cell]` return
  untyped `Variant`, routinely assigned straight into a typed local
  (`var enemy: EnemyAgent = enemies[cell]`). This is the codebase's
  deliberate style, not a mistake — don't "fix" it, and don't bother
  enabling GDScript's `unsafe_cast`/`unsafe_property_access` warnings
  against it (tried this; it's just noise against an intentional pattern,
  and GDScript analyzer warnings don't print in headless mode anyway, so
  there's no way to see them outside the interactive editor regardless).

## Testing pitfalls that have each cost real debugging time

- **The "instant flee" trap.** Flee checks run *before* any damage
  exchange. If you hand-craft wildly lopsided stats in a test (one side 10x
  the other), the weaker side often disengages on turn one, before the
  thing you actually wanted to exercise ever happens. Use moderate deltas
  (e.g. one side ~2x level/HP/strength, not 50x) unless the test is
  specifically about the flee threshold itself.
- **Stale array indices after a mutating event.** `game_manager._on_npc_died`
  erases from `main.npcs`, shifting indices. Never re-index
  `main.npcs[i]` after triggering something that might kill an NPC — hold a
  direct reference to the character you care about *before* triggering it.
- **Tweens don't resolve synchronously.** `_move_to()`/`_follow_to()` start
  a real `Tween`; calling it from a test and immediately asserting the
  post-move state will fail. Either call `_on_move_finished()` /
  `_follow_to()`'s completion directly to simulate arrival, or drive combat
  turns via the private `_resolve_*_turn`/`_run_*_turn` methods directly
  rather than waiting on `get_tree().create_timer()`.
- **Picking a "safe" test cell.** `_unrestricted_cells()` excludes safe
  zones but *not* cells a monster or chest already occupies — filter for
  `not enemy_map.has(c) and not chest_map.has(c)` too, or the enemy/chest
  check earlier in `_attempt_move` silently short-circuits before the code
  path you're trying to test ever runs.
- **A stale object reference across a death.** If something you hold a
  reference to might die and get *promoted away from* (e.g. a pack/party
  leader), re-fetch the current representative from the shared
  `enemy_map`/`player_map` dict rather than continuing to use your original
  reference — it may no longer be the leader, or may be a different
  instance than whatever took over.

## Git workflow

Never commit or push without being asked explicitly each time — this has
been the standing expectation throughout the project so far. When asked,
prefer splitting unrelated concerns (e.g. a gameplay feature vs. test
infrastructure) into separate commits.
