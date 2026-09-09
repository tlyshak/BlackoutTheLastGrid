# Plan — t04-hud-energy (T-04 · HUD енергії)

## Goal
Show the one resource the game is about: an on-screen energy bar bound to `GameState.Energy`, so
the T-03 drain and the T-05 recharge are visible without the Remote inspector. `GAME_DESIGN.md` §4
«Енергія як валюта. Одна шкала», §6 palette (warm yellow/orange = energy on cold concrete).

## Scope
- In: `scenes/ui/HUD.tscn` (`CanvasLayer`) + `scripts/ui/HUD.cs`; `ProgressBar` + numeric `Label`
  bound to `GameState.EnergyChanged`; a separate `Theme` resource `scenes/ui/HudTheme.tres`
  (placeholder styling, swappable later); HUD instance in `TestRoom.tscn`; smoke `tests/smoke/ui_hud.gd`.
- Out: art, animations of the bar, flashlight/weapon icons, coop second bar (architecture note
  only), a level loader in `Main.tscn` (the HUD moves there when levels are loaded through it).

## Design-doc conformance
§4 one shared scale; §6 warm accent for energy. Placeholder look, no art. No disagreements.

## Options considered
1. **HUD subscribes to `GameState.EnergyChanged` in code** (chosen): the bar is exact and
   event-driven; no per-frame polling; disconnect in `_ExitTree`.
2. Polling `GameState.Energy` in `_Process`: simpler but a per-frame read/write for nothing.
3. Bar under `TestRoom/UI` next to the debug label: couples HUD to the test level; the HUD must be
   its own scene so `Main.tscn`/levels can instantiate it (scene-design: "Main owns the HUD").

## GameState & save impact
Read-only consumer of `Energy`, `MinEnergy`, `MaxEnergy`, `EnergyChanged`. Nothing to persist.

## Scene & signal contract
```
HUD (CanvasLayer, layer 10) → scripts/ui/HUD.cs
├── Root (Control, full rect, mouse ignore, theme = HudTheme.tres)
│   └── EnergyPanel (MarginContainer, top-left, margins 16)
│       └── VBox (VBoxContainer)
│           ├── EnergyLabel (Label, "ЕНЕРГІЯ 100")
│           └── EnergyBar (ProgressBar, 260×18, show_percentage = false)
```
Exports on `HUD`: `EnergyBar` (ProgressBar), `EnergyLabel` (Label?), `LabelFormat` (string,
default "ЕНЕРГІЯ {0}", {0} = energy rounded to an int with `Mathf.RoundToInt`). API: `float DisplayedEnergy` (bar value), `void Bind(GameState)` (called
from `_Ready` with `GameState.Instance`; tests may rebind). Behaviour: `_Ready` sets `MinValue`/
`MaxValue` from the state, `Value = Energy`, label text; `EnergyChanged(float)` → `Value` + label;
`_ExitTree` disconnects. Signals: none (future: `LowEnergy` when a threshold export is crossed).
`HudTheme.tres`: `Theme` with `ProgressBar` `background` (dark `StyleBoxFlat` #141821, corner 3)
and `fill` (warm #f2b134, corner 3) and a `Label` font color #e8e2d0 — placeholder, swappable.
Owner: `TestRoom` instantiates `HUD` (stand-in for `Main` until a level loader exists); the debug
label moves down to y = 76 so both are readable.

## File-level change list
- scenes/ui: `HUD.tscn`, `HudTheme.tres` (new); scenes/levels: `TestRoom.tscn` (HUD instance, label offset)
- scripts/ui: `HUD.cs` (new)
- tests/smoke: `ui_hud.gd` (new)
- docs: this plan, TASKS.md note. project.godot: no change.

## Acceptance criteria
- Given `HUD.tscn` instantiated with `GameState` at 100, `EnergyBar.MinValue == MinEnergy`,
  `MaxValue == MaxEnergy`, `Value == 100`, label text "ЕНЕРГІЯ 100".
- Given `GameState.Energy = 42.4`, on the same frame `Value == 42.4` and the label reads "ЕНЕРГІЯ 42".
- Given `AddEnergy(-10)` and `ResetRun()`, the bar follows (32.4 → 100) without any `_Process` work.
- Given `TestRoom`, a `HUD` instance exists, the bar shows the drain while the flashlight is on
  (60 frames → −1.0 ± 0.05 on the bar), and freeing the room leaves no dangling connection
  (changing `Energy` after the free prints no error; a HUD removed from the tree stops following,
  re-added it follows again — C# `+=` subscriptions are invisible to `get_signal_connection_list`).
- Build, headless TestRoom load, smoke green.

## Test strategy
Smoke `tests/smoke/ui_hud.gd` (sync + a short async part for the drain): everything above. Only by
hand: colours, placement, readability against the dark room.

## Playtest (manual QA)
1. `TestRoom.tscn` (F6): зліва вгорі темна смуга з жовтою заливкою на всю довжину і напис
   «ЕНЕРГІЯ 100»; напис стану нижче, обидва читаються на темному тлі.
2. F (ліхтар): заливка повільно скорочується (~1 поділка/с), число падає 100 → 99 → …; F ще раз —
   зупиняється.
3. У Remote-інспекторі виставити `GameState.Energy = 10`: смуга миттєво стає короткою, напис «ЕНЕРГІЯ 10».
4. Стрибки, удари по манекену: смуга не смикається (шкода герою поки не наноситься).
5. У Remote-інспекторі `GameState.Energy = 0.5` → напис «ЕНЕРГІЯ 0»; потім `Energy = 0` → напис
   лишається «ЕНЕРГІЯ 0» (не «1»).

## Review focus
`signals/decoupling`, `GameState usage`, `scene/tscn integrity`, `exports/tunables`.

## Performance & frame budget
Zero per-frame work; one label string per energy change (≤ 60/s while the lamp is on — acceptable;
if it ever matters, throttle the label to integer changes).

## Risks
`EnergyChanged` fires every physics tick while the lamp drains; the label allocates a string each
time — mitigated by updating the label only when the rounded value changes.

## Open questions
None.

## Review findings

### Round 1 — Ship: yes

#### Summary
The branch adds the on-screen energy bar: `scenes/ui/HUD.tscn` (`CanvasLayer` layer 10 → `Root`
full-rect `Control` with `HudTheme.tres` → `EnergyPanel` `MarginContainer` → `VBox` → `EnergyLabel`
+ `EnergyBar` 260×18, `step = 0`, no percentage) driven by `scripts/ui/HUD.cs`, which subscribes to
`GameState.EnergyChanged` with a C# `+=` in `Bind()` (called from `_Ready`) and unsubscribes in
`_ExitTree`. `TestRoom.tscn` instantiates the HUD and moves the debug label down to y = 76; the
smoke `tests/smoke/ui_hud.gd` covers wiring, binding, same-frame updates, `Unbind()/Bind()`, free
without a dangling handler, and the flashlight drain on the bar. Reviewed surface = the full
uncommitted working tree (`git status --porcelain`: `HUD.cs` + `.uid`, `HUD.tscn`, `HudTheme.tres`,
`TestRoom.tscn`, `ui_hud.gd` + `.uid`, this plan, `TASKS.md`, and the deleted `scenes/ui/.gitkeep`
/ `scripts/ui/.gitkeep`); committed history (`T-03r`, docs) was reviewed earlier and is out of scope.

Verification (run by the reviewer): `dotnet build` — 0 warnings / 0 errors; `godot --headless
--path . --quit`, `... res://scenes/levels/TestRoom.tscn --quit-after 5`, `... res://scenes/ui/HUD.tscn
--quit-after 5` — no `ERROR:`/`WARNING:` lines; `tools/smoke.ps1` — `SMOKE SUMMARY: 6 passed, 0 failed`
(`ui_hud` included). Probes (scratchpad GDScript, `-s`): no `ERROR:` after `free()`-ing a bound HUD and
changing `Energy` (no leak); `EnergyBar.get_theme_stylebox("fill")` is identical (`==`) to the
theme's `StyleBoxFlat` and `EnergyLabel` resolves the theme's `font_color` (propagation works);
panel actual size 292×77, bar bottom at y = 61, debug label top at y = 76 (15 px gap, no overlap;
HUD layer 10 vs `UI` layer 1); rounding and re-entry defects below.

#### Plan conformance
Plan: `docs/plans/t04-hud-energy/t04-hud-energy-plan.md`
TASKS.md: T-04 `in_progress` — correct for this stage; the «Зроблено / Не зроблено» note, review
line and playtest list are not yet written (expected; `/coder` adds them before `done`).
- Implemented as planned: scene tree, layer, exports (`EnergyBar`, `EnergyLabel?`, `LabelFormat`),
  `DisplayedEnergy`, `Bind`/`Unbind`, `_Ready` min/max/value/label, `_ExitTree` disconnect; theme
  colours match the contract exactly (#141821 bg, #f2b134 fill, #e8e2d0 label; the 1 px border and
  text shadow are additive); HUD instance in `TestRoom`; smoke; `project.godot` untouched; no
  assets touched; §4 one scale / §6 warm accent respected.
- Deviates from plan: debug label moved to y = 76, not 64 (`scenes/levels/TestRoom.tscn:78`,
  `tests/smoke/ui_hud.gd:18`) — the code is right (bar ends at y = 61; 64 would sit 3 px under it),
  the plan line is stale. Acceptance criterion «probe via `get_signal_connection_list`» is not
  satisfiable for C# `+=` subscriptions (see T1) — the smoke follows it literally and the check is
  vacuous; the criterion is actually met by behaviour (no `ERROR:` after the free). `.gitkeep`
  removed from `scenes/ui/` and `scripts/ui/` — natural, not in the file list; mention in the commit body.
- Missing / partial: the Risks section's «update the label only when the rounded value changes» is
  implemented but breaks at exact `.5` values (S1).
- Accepted limitation (per plan): `TestRoom` owns the HUD as a stand-in for `Main` — residual risk:
  once `Main` keeps one HUD across level swaps by re-parenting it, the bar goes stale (S2); fix now
  while the file is small.
- Acceptance criteria: all literally true (smoke green); «done when: шкала оновлюється в реальному
  часі в `TestRoom`» holds (drain 60 frames → −1.0 on the bar, smoke line 227–231).

#### Code
Blockers: none.

- [x] **S1. Two rounding rules → stale label at `.5`, can show «1» at zero energy** —
  `scripts/ui/HUD.cs:67` / `:74` — Should-fix
  **Problem / why it matters:** `_shownRounded` uses `Mathf.RoundToInt` (= `MathF.Round`, banker's:
  32.5 → 32, 31.5 → 32, 0.5 → 0) while the text uses `string.Format("{0:0}", energy)` (away from zero:
  32.5 → «33», 0.5 → «1»). Once the value passes through an exact half the two disagree and the
  throttle then suppresses the correct text. Probe: `33.0` → «33»; `32.5` → «33» (`_shownRounded` =
  32); `32.4` → still «33» (should be «32»); `31.5` → still «33» (`RoundToInt` = 32 == 32, skipped —
  off by two); `0.5` → «1»; `0.4` → still «1»; from there `Energy = 0` (lamp dead) leaves the label at
  «1». Not reachable through the flashlight drain today (float accumulation never lands on an exact
  half), but any T-05 `Amount` / T-06 damage typed as `7.5` makes it a one-hit reproduction, and the
  Remote inspector reproduces it now.
  **Fix:** A (correct, one line) — format the already-rounded integer:
  `EnergyLabel.Text = string.Format(LabelFormat, rounded);` so one rounding rule governs both the
  throttle and the text (also removes the culture dependence of N5; document that `{0}` is an
  integer). B — keep the float but round it the same way:
  `int rounded = (int)MathF.Round(energy, MidpointRounding.AwayFromZero);`. Add the regression
  from T3.
- [x] **S2. HUD does not re-bind when it re-enters the tree** — `scripts/ui/HUD.cs:29` / `:32` —
  Should-fix
  **Problem / why it matters:** `Bind` runs in `_Ready` (once per node lifetime), `Unbind` in
  `_ExitTree` (every exit). A HUD that is removed and re-added — the plan's own next step, `Main`
  keeping one HUD while it swaps levels (`remove_child`/`add_child` or `reparent`) — comes back
  unbound and silently frozen. Probe: `remove_child(hud)`; `Energy = 50` → bar 100 (correct,
  unbound); `add_child(hud)` → `is_node_ready() == true`, `_Ready` not re-run, bar 100 while
  `Energy = 50`; `Energy = 60` → bar still 100, label «ЕНЕРГІЯ 100». Not reachable in `TestRoom`
  today (the HUD is freed with the room).
  **Fix:** A (correct) — `public override void _EnterTree() { if (IsNodeReady()) Bind(GameState.Instance); }`
  (exports are already resolved on re-entry, `_Ready` still handles the first entry). B (smallest) —
  `RequestReady()` at the end of `_ExitTree` so `_Ready` runs again on re-entry. Either way extend the
  smoke with the remove/re-add step from T1 so the fix is guarded.

#### Tests
- [x] **T1. Leak assertions are vacuous for C# events** — `tests/smoke/ui_hud.gd:60-68`, `:178-181`,
  `:248-249`. `get_signal_connection_list("EnergyChanged")` only ever contains the one
  `EventSignalMiddleman` connection Godot .NET installs on `GameState` itself; a C# `+=` subscriber
  is a managed delegate and never appears. Probe with the HUD alive and bound: total = 1, targeting
  the HUD = 0 — the same numbers as after the free, so lines 178/180/248 cannot fail on a leaked
  `Unbind`. The real guard is the implicit one on line 182 (a dangling handler on a disposed node
  throws `ObjectDisposedException`, logged as `ERROR:`, which the runner rejects) — keep it and say
  so. Replace the counting with an observable check of `_ExitTree`: `root.remove_child(hud)`;
  `gs.Energy = 50.0`; assert `bar.value` unchanged; `root.add_child(hud)`; `gs.Energy = 60.0`;
  assert `bar.value == 60` (fails until S2 is fixed — write it first, see it FAIL, then fix).
- [x] **T2. Theme-propagation check passes with the default theme too** — `tests/smoke/ui_hud.gd:123`.
  Godot's default `ProgressBar` `fill` is also a `StyleBoxFlat` (probe: true), so `is StyleBoxFlat`
  proves nothing about `HudTheme.tres` reaching the bar. Assert identity:
  `bar.get_theme_stylebox("fill") == theme.get_stylebox("fill", "ProgressBar")` (and the same for
  `background`); optionally `label.get_theme_color("font_color") == theme.get_color("font_color", "Label")`.
- [x] **T3. `.5` regression for S1** — `tests/smoke/ui_hud.gd` §3: `Energy = 32.5` then `32.4` →
  label «ЕНЕРГІЯ 32»; `Energy = 0.5` then `0.0` → «ЕНЕРГІЯ 0».
- Playtest: the plan's four steps are adequate; add «`Energy = 0.5` у Remote, потім 0 — напис 0»
  once S1 lands.

#### Nits
- Plan contract says the debug label moves to y = 64; the scene uses 76 — update the plan line, the
  code is right — `docs/plans/t04-hud-energy/t04-hud-energy-plan.md` (Scene & signal contract),
  `scenes/levels/TestRoom.tscn:78`.
- Plan acceptance criterion «probe via `get_signal_connection_list`» is unfulfillable for C# events —
  rewrite it to the remove/re-add observable check from T1.
- `EnergyPanel` `offset_bottom = 72.0` but its minimum size is 77 (label 23 + 4 + bar 18 + margins
  32); harmless (the container grows), the editor will rewrite it on first save —
  `scenes/ui/HUD.tscn:26`.
- `Root.mouse_filter = IGNORE` does not make the HUD click-through: `EnergyPanel`/`VBox` are PASS and
  `EnergyBar` is STOP (probe: 1/1/0), so the 260×18 bar swallows clicks. Irrelevant until a mouse UI
  exists; then set `mouse_filter = 2` on `EnergyPanel` (containers propagate it) — `scenes/ui/HUD.tscn:22`, `:40`.
- `LabelFormat` is an export, so a designer can type `{0:0.0}` and get a culture-dependent decimal
  separator («42,4» under uk-UA, probe «42.4» under en_US); a malformed format throws
  `FormatException` on every unit change (ERROR spam). If S1 option A lands, document that `{0}` is
  an integer; optionally validate the format once in `_Ready` with a `GD.PushWarning` fallback —
  `scripts/ui/HUD.cs:20`, `:74`.
- User-facing Ukrainian literal («ЕНЕРГІЯ») lives in a `.cs` default and a `.tscn` (UTF-8, loads
  fine). `GAME_DESIGN.md` has no localisation rule, so this is not a defect; if localisation ever
  becomes a goal, add a `backlog` line for `tr()` + translation CSV — `scripts/ui/HUD.cs:20`,
  `scenes/ui/HUD.tscn:38`.
- `Bind(null)` clears `_state` and then throws `NullReferenceException` at `:40` (probe); an
  `ArgumentNullException.ThrowIfNull(state)` before `Unbind()` gives a clearer message and leaves
  the previous binding intact — `scripts/ui/HUD.cs:36-40`.
- Deleted `scenes/ui/.gitkeep` and `scripts/ui/.gitkeep` are not in the plan's file list — fine,
  name them in the commit body.

#### What's done well
- Event-driven and zero per-frame work: no `_Process`, one string per whole-unit change, the bar
  tracks `Energy` exactly (`step = 0`, verified within the drain smoke).
- The free path is clean: `free()` / `queue_free()` on a bound HUD followed by `Energy` changes
  prints no `ERROR:` (probe) — the `_ExitTree` unsubscribe works and `TestRoom.cs` was left untouched.
- Scene/resource integrity is spotless: unique uids (`2adcecasbtv6`, `4i2jy3f0qvhf`), correct
  `load_steps` (3/3/6), `node_paths` resolve, `.uid` sidecars follow the repo convention, and the
  HUD lives on its own `CanvasLayer` so `TestRoom`'s `CanvasModulate` darkness does not touch it.
- `HudTheme.tres` is genuinely swappable: the bar and label pick every colour from the theme
  (identity-verified), and the palette is the §6 warm accent on cold concrete to the exact hex.
- The smoke is thorough where it counts (same-frame updates, `Unbind`/`Bind` API, drain equation,
  TestRoom wiring), guards every null path to `quit()`, and its comment honestly states the
  ERROR-line guard.

#### Verdict
Ship: yes — no blockers; build, headless loads and all six smokes are green, and the leak path is
verified clean. Two Should-fixes are real, cheap and belong in this fix-pass: the `.5` rounding
mismatch (S1) will surface the moment T-05/T-06 use half-unit amounts, and the re-entry rebind (S2)
is the plan's own next owner scenario. First: 1) S1 — format `rounded`, add T3; 2) S2 — rebind in
`_EnterTree` when `IsNodeReady()`, guarded by the T1 remove/re-add step; 3) T1/T2 — replace the
vacuous listener count and the `is StyleBoxFlat` check with identity/observable assertions.
