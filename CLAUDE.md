# DungeonSim

A Godot 4.7 (GDScript) spectator simulation: 20 autonomous, AI-controlled
characters explore a procedurally generated maze, gain RPG levels through
encounters, form parties, fight monsters and each other, and race for a
boss room at the center. Each `NpcAgent` drives itself from `_process`; the
spectator can only watch, pause, inspect (click a character or gravestone),
toggle the fog of war / Party Vision, and give the selected party Guidance
(right-click a cell, on a cooldown) — they never control anyone directly.

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

The repo tracks Godot's `.uid` files; the same command generates them for
new scripts.

## Running tests

The test suite is [GUT](https://github.com/bitwes/Gut) 9.7.1, vendored into
`addons/gut` (not a submodule — just vendored files, MIT licensed). Tests
live in `tests/unit/`, one file per concern.

```
godot --headless --path . -s addons/gut/gut_cmdln.gd
```

`.gutconfig.json` in the project root already points the runner at
`tests/unit`, so no extra flags are needed. Exits 0 on success, 1 if any
test fails — safe to gate CI on (see `.github/workflows/tests.yml`). The
whole suite takes about 30 seconds.

Test scripts extend **`DungeonTest`** (`tests/dungeon_test.gd`, outside
`tests/unit` so GUT doesn't collect it) rather than `GutTest`. It provides
`main` / `load_main()` for tests that need the whole generated game, plus
the shared helpers: `clear_cell()`, `set_stats()`, `new_enemy()`,
`rank_npcs_by_index()`, `click_on()`, and hand-built mazes
(`walled_grid()`, `open_between()`, `corridor()`, `ring_maze()`). Add a
helper there rather than copying it into a second test file. Pure logic
(`NpcStats`, `CombatMath`, a bare `MazeGenerator`) is tested without loading
`Main` at all.

## Where things live

- **`game_manager.gd` (`GameManager`)** — the running session: input
  (clicks, Guidance), fog of war and Party Vision syncing, the selection
  ring, gravestones, and the event handlers (`_on_npc_died`, ...). Owns the
  world's shared state — `grid`, `player_map`, `enemy_map`, `chest_map`,
  `restricted_cells`, `npcs` — which everything else reads.
- **`world_builder.gd` (`WorldBuilder`, as `main.world`)** — generates the
  maze and its zones and stocks it (monsters, bosses, chests), plus chests
  placed later (mini boss drops, death chests). Writes into GameManager's
  state rather than keeping its own.
- **`monster_respawner.gd` (`MonsterRespawner`, as `main.respawner`)** —
  splits the maze into 8x8 areas, remembers each area's starting monster
  count, and slowly respawns lost monsters out of every player's sight, never
  above that count. Monsters belong to the area of their *home* cell (they're
  leashed to it).
- **`npc.gd` (`NpcAgent`)** — one character: exploring, movement, chests,
  shopping, consumables, Guidance, sight (`seen_cells`/`sight_cells`), its
  map label, and its own combat tactics (`choose_combat_action`,
  `apply_combat_action`). Still the biggest file.
- **`group_combat.gd` (`GroupCombat`)** — the two fight loops (party vs
  monster pack, party vs party) as static functions, turn-paced by SceneTree
  timers.
- **`party_ops.gd` (`PartyOps`)** — party merging, naming, leader promotion,
  `leader_of(party)`, and item sharing. **`combat_math.gd` (`CombatMath`)** —
  pure hit/damage/win-chance math over two `NpcStats`.
- **`hud.gd` (`Hud`)** — toolbar, the leaderboard (top 10, right column, compact panels without the gear section), and
  the selection column (the selected character's full panel, then compact
  ones for the rest of their party, on the left).
- **`battle_window.gd` (`BattleWindow`, as `hud.battle_window`)** — the
  Final Fantasy-style battle screen below the selection column. GameManager
  says who's in the scene every frame (`show_fight`: the selected party and
  `GroupCombat.opponents_of` them) and forwards every `NpcAgent.combat_event`
  (sent by `GroupCombat._report`, one per blow, spell or heal), which it
  queues and plays out in turn. It draws from its own snapshots, never the
  live nodes, so a monster the game has already freed can still dissolve.

## Architecture conventions worth knowing before touching combat/party code

- **Static helpers over the agents' own fields.** `PartyOps` and
  `GroupCombat` are static functions taking the `NpcAgent`(s) involved
  explicitly; they still read/write fields that live on the agent (`party`,
  `is_party_leader`, `in_pvp_combat`, ...). It's a static-utility split, not
  an ownership change. An `NpcAgent` method that another class calls has a
  public name (`die()`, `move_to()`, `reset_label()`, ...); underscore
  methods are only called from within `NpcAgent` — and from tests.

- **Leader/follower pairs, twice.** Both player parties (`NpcAgent.party`)
  and enemy packs (`EnemyAgent.pack`) use the same pattern: one leader makes
  decisions (explore, fight, wander) and runs its own `_process`/think-loop;
  followers just tag along visually (`_follow_to` / `_follow_pack_move`) and
  join combat when the leader does. If a leader dies, a follower is
  promoted automatically (`PartyOps.promote_next_leader` /
  `EnemyAgent._promote_next_pack_leader`) — this is load-bearing: without
  it, the survivors would freeze forever, since only leaders ever act.
  Anything the leader carries for the party (a Guidance target, its map
  label mid-message) has to be handed over on promotion too.

- **Two different "who represents this cell" dicts.** `GameManager` owns
  `player_map` (cell → party leader) and `enemy_map` (cell → pack leader),
  both shared by reference into every `NpcAgent`/`EnemyAgent`. A character
  is *never* independently discoverable through these dicts unless it's
  currently a leader — followers simply aren't in them.

- **Combat identifies sides by party array reference, not by cell.**
  `GroupCombat.run_pvp_turn`/`run_pack_turn` re-derive "who's currently
  driving each side" every turn via `PartyOps.leader_of(party)` (so a
  mid-fight leader death hands off cleanly), and PvP keys off the two
  `party` array references rather than cell coordinates. Two parties can
  legitimately occupy the same cell (one found the other already standing on
  its own square), and a cell-keyed lookup collapses both sides into the same
  dict entry when that happens — this was a real, shipped bug (both sides
  became the same object, freezing the fight with no progress) before it was
  caught by `test_pvp_does_not_freeze_when_both_sides_share_a_cell`. If you
  add a new multi-character interaction keyed by cell, ask whether the two
  sides can ever coincide on one cell before assuming the lookup is unique.

- **Fight turns are static callbacks, so they outlive the scene.** A turn's
  timer calls straight back into a `GroupCombat` static function, not a
  method on any node — so it still fires after its scene (e.g. a test's
  `main`) has been freed. Look monsters up through `GroupCombat.pack_at()`,
  which copes with freed entries, rather than typing `enemies.get(cell)`
  straight into an `EnemyAgent`.

- **`die()` clears its own `in_pvp_combat`/`in_combat`-adjacent state
  directly**, rather than relying on a cleanup pass that walks the party
  array afterward — `party.erase(self)` mutates that array in place, so a
  cleanup step running after the erase can no longer find the member it
  needs to unlock.

- **`NpcAgent`s are never freed.** `die()` sets `dead = true` and
  `visible = false` but the node stays in the tree forever (so signals/HUD
  rows keep working). `is_instance_valid()` on an `NpcAgent` is therefore
  always true — check `.dead`, not instance validity. `EnemyAgent` and
  `ChestAgent` *are* `queue_free()`'d on defeat/collection, so
  `is_instance_valid()` matters there.

- **Map labels go through `show_label()` / `reset_label()`.** Never set
  `name_label.text` directly: `show_label(text, seconds)` marks the label
  busy (a passing message counts down in `_process`, so it pauses with the
  game; `seconds = 0` means until `reset_label()`, e.g. at the end of a
  fight). Only a party's leader shows a label, under the party's name;
  `sync_label()` handles that whenever a party changes shape, and leaves a
  busy label alone.

- **Icons move through `slide_to()`, one slide at a time.** A new slide
  stops the one under way, dropping its finished callback, so the last
  move issued decides both where the icon ends up and what `cell_pos`
  says. The fog is lit from `cell_pos`, so when two tweens on `position`
  overlapped (or a fight's winner "claimed" a loser's cell that wasn't next
  door), walls stayed lit around a spot the icon had left. Don't
  `create_tween()` on a character's `position` directly, and only `move_to()`
  an open neighbour (see `GroupCombat.claim_cell`).

- **`players` entries can be stale; check with `NpcAgent.holds_cell()`.**
  An entry only counts if it's a living party leader whose `cell_pos` is
  that cell. A leftover entry once let parties fight someone on the far
  side of the maze.

- **Each character keeps its own map (`seen_cells`).** Updated by
  `look_around()` when it moves, pooled across a party when it forms
  (`PartyOps.pool_seen_cells`) and shared as members see more. Party Vision
  draws the fog from the selected party's map; Guidance plans its A* route
  over it (`MazeQuery.explore_step`, unseen passages assumed open).

- **"Safe rooms" = `GameManager.restricted_cells`**, exposed to each
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
  The one exception is the static fight callbacks above.

## Testing pitfalls that have each cost real debugging time

- **The "instant flee" trap.** Flee checks run *before* any damage
  exchange. If you hand-craft wildly lopsided stats in a test (one side 10x
  the other), the weaker side often disengages on turn one, before the
  thing you actually wanted to exercise ever happens. Use moderate deltas
  (e.g. one side ~2x level/HP/strength, not 50x) unless the test is
  specifically about the flee threshold itself.
- **Stale array indices after a mutating event.** `GameManager._on_npc_died`
  erases from `main.npcs`, shifting indices. Never re-index
  `main.npcs[i]` after triggering something that might kill an NPC — hold a
  direct reference to the character you care about *before* triggering it.
- **Tweens don't resolve synchronously.** `move_to()`/`_follow_to()` start
  a real `Tween`; calling it from a test and immediately asserting the
  post-move state will fail. Either call `_on_move_finished()` directly to
  simulate arrival, or drive fight turns via `GroupCombat.resolve_*_turn` /
  `run_*_turn` directly rather than waiting on the turn timers.
- **Picking a "safe" test cell.** `main.world.unrestricted_cells()` excludes
  safe zones but *not* cells a monster or chest already occupies — use
  `clear_cell()`, or the enemy/chest check early in `_attempt_move` silently
  short-circuits before the code path you're trying to test ever runs.
- **A stale object reference across a death.** If something you hold a
  reference to might die and get *promoted away from* (e.g. a pack/party
  leader), re-fetch the current representative from the shared
  `enemy_map`/`player_map` dict (or `PartyOps.leader_of`) rather than
  continuing to use your original reference.
- **Never `await wait_seconds()` while the tree is paused** — GUT's own
  waiting pauses with it and never returns, hanging the run. Wait on a
  process-always timer instead: `await get_tree().create_timer(t, true).timeout`.
- **Every run is a different random maze.** Tests that lean on the layout
  ("a neighbour shows something new", "this cell is far from everyone") can
  pass for weeks and then fail one run in eight. Search for a cell that
  meets the need, or build a small maze by hand (`walled_grid()` and
  friends), rather than assuming one is next door. Run the suite several
  times after adding such a test.
- **GUT's orphan counts after HUD tests are expected.** Discarded panels
  are removed from their column straight away and freed at the end of the
  frame (`Hud._discard_panel`); GUT counts orphans in between.
  `test_discarded_panels_are_freed_not_leaked` checks they really are freed.

## Git workflow

Never commit or push without being asked explicitly each time — this has
been the standing expectation throughout the project so far. When asked,
prefer splitting unrelated concerns (e.g. a gameplay feature vs. test
infrastructure) into separate commits, and stage files by name rather than
`git add -A`.
