# CLAUDE.md — Neural Glass

> Working title. A Roblox experience that makes MNIST digit classification visible.
> **Status:** M3 and M4 code committed, but neither playtest checklist is confirmed and M4's budgets are unmeasured; M5 waits on that. Model `b665ebc1`: float 98.34%, int8 98.32%, no recorded fixtures yet. Update this line as milestones land.

The player draws a digit (0–9) on a drawing pad. While they draw, a small neural network running in Luau classifies it live, and the forward pass plays out inside **the Glass**: a glass chamber where signals flow from the 28×28 image the network sees, through two layers of glowing neurons, to ten output nodes, where the winning digit lights up.

This file is the spec and the working agreement for Claude Code. When a decision or command changes, update this file in the same commit.

**Stack:** Luau on Roblox, synced from disk with Rojo · Lune for headless tests · Python + PyTorch for training and export.

## Hard rules

1. **Files are the source of truth.** All code lives on disk and reaches Studio through Rojo. Never edit scripts inside Studio, including with the Studio MCP write tools (`multi_edit`): those edits diverge from git and get overwritten.
2. **Never hand-edit generated files:** `src/shared/NeuralCore/ModelData.luau`, `src/client/Dev/Fixtures.luau`, `tests/golden/*`. Regenerate them with `python -m training.export`.
3. **Preprocessing parity.** `NeuralCore/Preprocess.luau` and `training/preprocess.py` implement one spec (below). Change both in the same commit, regenerate goldens, keep the parity tests green.
4. **Drawings stay private.** A player's strokes never reach another player: no spectating, galleries or shared replays, and nothing stores, logs or forwards strokes (the Studio-only Dev harness is the one exception). The only network hop is a one-shot submit to the server, which scores and discards. Roblox limits experiences with "free-form user creation" (2D drawings replicated to others without moderation) to players 13+, so this is a deliberate design constraint. Ask the human before changing it.
5. **No `Enum.Material.Glass` in the Glass.** Glass material hides non-opaque objects behind it (beams, particles, SurfaceGuis, transparent parts), which are exactly the signals. Fake the pane with SmoothPlastic and transparency.
6. **`NeuralCore` is pure Luau.** No `game`, services, Instances, `task` or Roblox datatypes (Vector2, Color3, …), so it runs unchanged under Lune.
7. **No per-frame allocation in hot paths.** No `Instance.new` after the Glass is built (pool everything) and no new tables per frame or per inference. Stay inside the budgets below.
8. **Don't trust the client.** The server recomputes the prediction for scoring; every remote validates types and sizes and is rate-limited.

## The experience

1. The player walks up to a **station** and triggers its "Draw" ProximityPrompt. In Draw Mode the camera locks onto the Glass, movement is disabled and the Pad slides in.
2. **Challenge:** the server asks for a digit ("Draw a 7"). **Free Draw:** no prompt, just explore.
3. While they draw, inference runs live and the Glass animates: the network-view panel shows what the model actually sees (scaled and centered), signals pulse left → right, neurons glow, output bars rise and fall. A live top-3 also appears in the HUD.
4. **Submit** (Challenge): the server scores it (top-1 == target) and updates score and streak; the client celebrates, or shows "The network saw a 9 (61%)" with the strongest path highlighted.
5. Clear or Undo and go again; Exit restores the camera and controls.

Stretch goals (after M6): neuron inspector (click an H1 neuron to see its 28×28 weight map on the network-view panel), slow-motion "explain" replay, "fool the network" challenge.

## Architecture

```text
CLIENT (per player; nothing here replicates)
  Pad --strokes, u16 at capture--> Preprocess --784 floats--> Model.forward --acts, probs--> Explain.selectEdges
                                       |                                                         |
                                       +--------> GlassView: network view, orbs, links, packets <-+  (lagged + smoothed)

  Submit --Strokes.encode -> buffer--> SERVER: Strokes.decode > Preprocess > Model > score > leaderstats  (strokes dropped)
```

Decisions (don't relitigate without the human):

| Decision                                                              | Why                                                                                                                |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Inference on the client; the server re-runs it only on submit         | Live feedback with no latency; the server stays authoritative for scoring                                          |
| MLP 784 → 64 → 32 → 10 (ReLU, softmax)                                | Few enough neurons to show every one; ~97–98% on MNIST; ≈15k multiply-adds per inference thanks to input sparsity  |
| int8 weights with a per-neuron scale, base64 in a generated module    | Under 80k characters of source, well below the 200k script limit                                                   |
| Pad ink and network view built from Frames, not EditableImage         | EditableImage needs a 13+ ID-verified owner plus a Security toggle, and only one displayed image updates per frame |
| Strokes are vectors, quantized to u16 when captured                   | Resolution-independent preprocessing, tiny payload, bit-identical input on client and server                       |
| The Glass is built procedurally on the client from the model's shapes | Changing layer sizes never needs Studio work                                                                       |

## Repo layout

```text
default.project.json  rokit.toml  selene.toml  stylua.toml  .luaurc  scripts/
src/
  shared/                  -> ReplicatedStorage.Shared
    NeuralCore/            pure Luau (Roblox + Lune); flat files, no init.luau
      ModelData.luau       GENERATED: weights + preprocessing constants
      Model.luau           load/dequantize once; allocation-free forward()
      Preprocess.luau      strokes -> 28x28 (spec below)
      Strokes.luau         stroke storage, limits, buffer encode/decode
      Explain.luau         picks which links the Glass shows
      Base64.luau
    Config.luau            every tunable: rates, budgets, colors, layout
    Assets.luau            uploaded asset IDs (textures, sounds)
  client/                  -> StarterPlayer.StarterPlayerScripts.Client
    Main.client.luau       bootstrap: stations -> Glass; Pad -> inference -> Glass
    Pad/  Glass/  Hud/
    Dev/Harness.luau       Studio-only test hooks; Dev/Fixtures.luau is GENERATED
  server/                  -> ServerScriptService.Server
    Main.server.luau  World.luau  Stations.luau  Rounds.luau  Submissions.luau
training/                  __init__.py config.py preprocess.py train.py export.py eval_strokes.py requirements.txt
tests/                     run.luau  *.spec.luau  lib/  golden/ (GENERATED)  fixtures/strokes/
assets/                    source PNGs and sounds; hand-made *.rbxm decor mapped by the project file
```

- Remotes are declared in `default.project.json` under `ReplicatedStorage.Net` (`Submit`: RemoteFunction; `Round`, `Station`: RemoteEvent) so they exist before any script runs. Lighting and its BloomEffect are declared there too.
- `server/World.luau` builds the lab and the station anchors from Config. Anything decorated by hand in Studio must be exported to `assets/*.rbxm` and mapped in the project file: `rojo build` alone must reproduce the whole place.
- Requires: inside `NeuralCore`, relative string requires only (`require("./Model")`), which resolve the same in Roblox and Lune. Everywhere else, instance requires (`require(ReplicatedStorage.Shared.NeuralCore.Model)`). The client bootstrap waits for `game.Loaded` before requiring NeuralCore.
- `.gitignore`: `build/ sourcemap.json training/data/ training/out/ .venv/ Packages/ __pycache__/`. `ModelData.luau` **is** committed so the game builds without Python.

## Commands

```bash
rokit install                          # tools pinned in rokit.toml: rojo, lune, stylua, selene, luau-lsp
rojo serve                             # live sync; the human connects the Rojo plugin in Studio
rojo build -o build/NeuralGlass.rbxl   # headless build; must always succeed
rojo sourcemap default.project.json -o sourcemap.json
scripts/check.sh                       # everything below plus the build; the exact CI invocation
stylua src tests                       # CI: stylua --check src tests
selene src
lune run tests/run                     # unit + golden parity tests, no Studio needed

uv venv --seed --python 3.12 .venv      # torch has no wheels for very new Pythons; 3.11 to 3.13 are safe
python -m pip install -r training/requirements.txt   # inside the venv: torch, torchvision, numpy
python -m training.train               # -> training/out/model.pt; prints float test accuracy
python -m training.export              # -> ModelData.luau, Dev/Fixtures.luau, tests/golden/*; prints accuracies
python -m training.eval_strokes        # accuracy on recorded drawings in tests/fixtures/strokes
```

Tool versions are pinned in `rokit.toml`. `scripts/check.sh` also type-checks `src` with `luau-lsp`, downloading the Roblox definitions matching the pinned version into `build/` on first run.

## NeuralCore contracts

### ModelData.luau (written by `training/export.py`)

```lua
-- AUTO-GENERATED by training/export.py. DO NOT EDIT.
return {
	formatVersion = 1,
	modelVersion = "3f9a1c2e", -- first 8 hex chars of sha256(weights); shown small in the HUD
	preprocess = { grid = 28, box = 20, brushInner = 1.0, brushOuter = 2.0, minExtent = 0.04 },
	layers = {
		{
			inSize = 784, outSize = 64, activation = "relu",
			weights = "<base64 int8>", -- input-major: byte (i * outSize + o), 0-based
			scales = {}, -- outSize numbers: w = q * scales[o]
			biases = {}, -- outSize numbers
			actScale = {}, -- outSize numbers: p99 activation on validation data (dead neuron -> 1); visuals only
		},
		-- { inSize = 64, outSize = 32, activation = "relu", ... },
		-- { inSize = 32, outSize = 10, activation = "softmax", ... },
	},
	metrics = { floatTestAcc = 0, int8TestAcc = 0, strokeFixtureAcc = 0 },
}
```

- Write floats with Python `repr()` so Luau parses exactly the same doubles.
- `strokeFixtureAcc` is -1 until fixtures are recorded. Generated Luau is listed in `.styluaignore`.
- The exporter fails if a generated module exceeds 190,000 characters (see Roblox facts). A bigger future model shards into `ModelData_2.luau`, and so on.
- Luau reads every shape from this file. Nothing may hardcode 784, 64, 32 or 10.

### Strokes

- Pad space: (0, 0) is top-left, y points down; coordinates are integers 0..65535 from the moment they're captured.
- In memory: flat arrays `xs`, `ys`, `strokeEnds` (index of each stroke's last point). A one-point stroke is a dot.
- Limits: at most 32 strokes and 1,024 points in total.
- Wire format (`buffer`, little-endian): `u16 strokeCount`; then per stroke `u16 pointCount` followed by `pointCount × (u16 x, u16 y)`. At most 4,162 bytes. The decoder rejects anything malformed, over the limits, or with bytes left over.

### Preprocess: MNIST-style, identical in Luau and Python

MNIST digits were scaled to fit a 20×20 box (aspect preserved), anti-aliased, then centered in 28×28 by center of mass. We reproduce that from vectors:

1. Convert coordinates to [0, 1] (÷ 65535). No points → return `false` (empty).
2. Take the bounding box of all points. If `max(w, h) < minExtent` → return `false` (the HUD says "draw bigger").
3. `s = box / max(w, h)`. Map each point into grid space with the box centered: `x' = (x − minX)·s + (grid − w·s)/2`, and the same for y. Pixel (c, r) covers [c, c+1) × [r, r+1); its center is (c + 0.5, r + 0.5).
4. Rasterize: intensity = `clamp((brushOuter − d) / (brushOuter − brushInner), 0, 1)`, where `d` is the distance from the pixel center to the nearest segment (or dot); segments combine with max. Only visit pixels within `brushOuter` of each segment's bounding box.
5. Compute the intensity-weighted center of mass `(cx, cy)`, shift every point by `(grid/2 − cx, grid/2 − cy)`, and rasterize again. Shifting the vectors gives exact sub-pixel centering.
6. Output 784 floats in [0, 1], ink = 1, row-major with row 0 at the top (Luau index `r*28 + c + 1`). No mean/std normalization.

Calibrate `brushInner`/`brushOuter` in `training/config.py` so recorded fixture digits average about 100 total ink (MNIST's mean pixel value 0.1307 × 784 ≈ 102).

### Model and Explain APIs

```lua
local model = Model.load(ModelData)                             -- decode + dequantize once
local scratch = Model.newScratch(model)                         -- preallocated arrays, reused forever
local top, pTop = Model.forward(model, input, scratch)          -- fills scratch.acts[layer], scratch.probs, scratch.top
local edges = Explain.newEdges(model)                           -- preallocated once
local count = Explain.selectEdges(model, input, scratch, edges) -- fills `edges`; call after forward with the same scratch

local ok = Preprocess.run(ModelData.preprocess, strokes, Preprocess.newScratch(), output) -- reuse both; false = unreadable
```

- `top` is 0-based, so it is the digit. Every other index (`scratch.acts`, `edges.src`, `edges.dst`) is 1-based.
- `edges` is a struct of arrays: `layer`, `src`, `dst`, `value`, `normalized`. Output links list the forced contributors first.

- Layer 1 skips zero pixels (most of the input): for each non-zero pixel `i`, add `x_i · W[i, :]` to the accumulators. Later layers skip zero ReLU outputs.
- Softmax subtracts the max logit. Argmax ties go to the lowest index.
- Explain picks at most 256 links: input → H1, the 16 most active H1 neurons × each one's top 6 positive pixel contributions (96); H1 → H2, the top 96 pairs by |a·w|; H2 → output, the top 64 pairs, always including the 8 largest contributors to the predicted digit. Each edge records layer, src, dst, the signed value, and the value ÷ that layer's max |value|. Ties break toward the lower index so tests are deterministic.
- `--!native` on these modules only takes effect on the server; budget the client for the interpreter.

## Training & export (`training/`)

- PyTorch + torchvision MNIST with fixed seeds. `config.py` is the single source for the architecture and preprocessing constants.
- **Domain gap:** MNIST is scanned pen strokes; players draw with a mouse or a finger. Augment with affine transforms (±12°, scale 0.85–1.15, slight shear, ±2 px shift), stroke-thickness jitter (dilate/erode) and mild blur. If real-drawing accuracy lags, re-render training digits in the game's own style: skeletonize MNIST digits and rasterize the skeleton with the game brush.
- **Quantization:** symmetric int8 per output neuron (`scale = max|w| / 127`), round, clamp to ±127. Biases stay float.
- **Targets:** float test accuracy ≥ 97%; int8 within 0.3 points of float; once at least 50 recorded fixtures exist, ≥ 90% on them. Report all three after every retrain.
- **Goldens:** the exporter writes (a) 32 MNIST test images with their expected logits and (b) 16 seeded random polylines plus every recorded fixture with the expected 784-vector and logits. Expected values come from a float64 NumPy forward pass over the _dequantized_ int8 weights, never from the float32 PyTorch model. Vectors are stored as base64 float64 so they round-trip exactly.
- **Fixtures** are drawings made by the developers with `Harness.dumpStrokes()`, saved as `tests/fixtures/strokes/<digit>_<n>.b64`; never player data. `Dev/Fixtures.luau` gets up to 3 per digit, under the same 190k limit.
- Credit MNIST (LeCun, Cortes, Burges) in the experience description.

## The Glass (`src/client/Glass/`)

Layout, left → right (input → output), inside a chamber behind a fake-glass pane:

1. **Network view:** a 28×28 SurfaceGui grid of Frames showing exactly the model's input. It quietly teaches the scaling and centering.
2. **H1:** 64 orbs (8×8). **H2:** 32 orbs (4×8).
3. **Output:** 10 orbs in a column with digit labels and probability bars; the winner gets a halo and a large "7 · 94%".

Encoding:

- Neuron brightness and size = `clamp(a / actScale, 0, 1)`. Output orbs and bars use the probability instead, which reads better than a scaled logit.
- Links are Beams between Attachments showing the contribution `a_src · w`: color is the sign (positive cyan-blue, negative orange, a colorblind-safe pair); width and brightness follow the normalized |value|.
- Packets (small Neon balls) travel along the shown links, spawning at a rate proportional to |value|. Negative packets are also smaller, so the sign never relies on color alone.
- Propagation: neuron values chase their targets with a per-layer lag (H1 80, H2 160, output 240 ms) and exponential smoothing (τ ≈ 120 ms), so packets "arrive" as the next layer lights up. The network view and links update at once, unsmoothed, so the view always shows exactly what the model saw.
- Empty pad → idle shimmer: dim breathing orbs and a few ambient packets. A reduced-motion setting turns packets off and keeps the links.

Build rules:

- `GlassBuilder` creates everything once and pools it: 106 orbs, 256 Beams, 96 movable pixel Attachments, 300 packets, labels. After that, hide unused items; never create or destroy.
- A single per-frame connection (`RunService.PreRender`) drives all animation; no TweenService on these objects. Move packets with one `workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)` call per frame. Skip property writes when the change is below an epsilon.
- Parts: Anchored; CanCollide, CanQuery, CanTouch and CastShadow all false. Beams: `FaceCamera = true`, `LightInfluence = 0`, `Segments = 1`. SurfaceGuis: `LightInfluence = 0`.
- Pane: SmoothPlastic, Transparency ≈ 0.9, slight Reflectance and tint, solid frame. Dark lab; BloomEffect for glow.
- It must stay readable at graphics quality 1, where glow and bloom are weak: carry meaning with contrast and size.

Budgets (mid-range phone, interpreted Luau): Glass update ≤ 2 ms per frame; preprocess + forward + explain ≤ 3 ms per inference; at most 10 inferences per second while the drawing changes, one at each stroke end, none while idle; the Glass uses ≤ 2,000 instances.

## The Pad (`src/client/Pad/`)

- ScreenGui with `ResetOnSpawn = false`. The square pad docks left in landscape and at the bottom in portrait; the camera frames the Glass in the rest of the viewport (recompute on resize and orientation change).
- Input: start on the pad's `InputBegan` (MouseButton1 or Touch). Mouse: track `MouseMovement` while the button is held. Touch: track only the InputObject that started the stroke and ignore other fingers. Finish on `InputEnded`. Convert positions with the pad's AbsolutePosition/AbsoluteSize, and check the GUI inset once with a mouse and once in the Device Emulator.
- Add a point only after the pointer moves ≥ 1% of the pad size; quantize to u16 immediately; enforce the Strokes limits (HUD: "Clear to keep drawing").
- Ink: pooled Frames (rotated segments plus round joints with UICorner), at most 2,048.
- Controls: Clear, Undo stroke, Submit (Challenge), Exit; keys C, Z, Enter, Esc. On gamepad, B exits; drawing with a gamepad is out of scope for v1.
- Draw Mode sets the camera to `Scriptable` and disables character controls (`PlayerModule:GetControls():Disable()`); restore both on exit and on respawn.

## Server & networking (`src/server/`)

- **Stations:** the ProximityPrompt's `Triggered` → the server grants the station (one player each) → the `Station` event puts that client in Draw Mode. Released on exit, death or leaving. The server builds the Stations model with `ModelStreamingMode = Persistent`.
- **Rounds:** per-player `{mode, target, streak, score}`. Targets are random but never repeat the last two. `leaderstats` shows Score and Streak (numbers only).
- **Submit** (RemoteFunction, client → server): at most 2 per second per player; payload ≤ 8 KB; `Strokes.decode` with limits → `Preprocess` → `Model` → compare with the target → return `{correct, predicted, prob, target}`. Then drop the strokes: never store, log, print or forward them.
- DataStores, persistence and monetization are out of scope until the human asks.

## Roblox facts this design relies on (checked Nov 2026)

- **Glass material** doesn't show non-opaque objects behind it (transparent parts, particles, beams, world-space GUIs). → Rule 5.
- **EditableImage** in published games needs an owner who is 13+ and ID-verified, plus _Allow Mesh / Image APIs_ in Game Settings → Security; only one displayed EditableImage updates per frame. → Frames instead.
- **`--!native`** compiles server-side scripts only. Players' devices run client code in the interpreter, and Studio on a desktop flatters client timings.
- **`Script.Source`** is capped at 200,000 characters when set from Studio or plugins, and Rojo's live sync is a plugin. → 190k exporter limit.
- **Require-by-string** works in Roblox (`./`, `../`), but `init` files resolve differently from Rojo's convention. → No `init.luau` in NeuralCore.
- **Free-form user creation** (2D drawing or writing replicated to others without moderation) restricts an experience to players 13+. Under-13s also can't play unrated experiences, so the human fills in the maturity questionnaire before publishing. → Rule 4.
- **StreamingEnabled** is on by default for new places and can't be changed from scripts. Client code `WaitForChild`s station anchors.
- **Client-created instances don't replicate.** That's intended: each player's Glass is theirs alone.
- **Buffers** can be sent through remotes; ours are capped at 8 KB.
- **`RenderStepped`** is superseded by `PreRender` for new work.

If the engine behaves differently from this list, tell the human and update it.

## Code style

- `--!strict` in every Luau file; `export type` for public shapes; no `any` in NeuralCore.
- StyLua defaults, selene clean. PascalCase modules and types, camelCase functions and locals, UPPER_SNAKE constants.
- Get services at the top via `game:GetService`. No globals, `_G` or `shared`. Use `task.*`, never `wait`, `spawn` or `delay`.
- Hot loops: numeric `for`, math functions cached in locals, `table.create(n, 0)` plus reuse, no closures created inside loops.
- Track every connection and disconnect it on cleanup (one small `Cleanup` utility, no frameworks).
- No magic numbers in Pad or Glass code; they go in `Config.luau`.
- No third-party runtime packages; ask first.
- Python 3.11+, type hints, scripts runnable as `python -m training.<name>`; no notebooks in the repo.

## Verifying your work

Definition of done for every change:

1. `stylua --check src tests` and `selene src` are clean.
2. `lune run tests/run` passes, including parity: Luau preprocessing within 1e-9 per pixel of Python, Luau logits within 1e-6 with the same argmax.
3. `rojo build -o build/NeuralGlass.rbxl` succeeds.
4. Changed the Pad, Glass, HUD or server flow → playtest through the Studio MCP server if it's connected; otherwise finish with a short manual playtest checklist for the human.
5. Retrained → report float, int8 and fixture accuracy and the new `modelVersion`, with goldens regenerated in the same commit.

**Studio MCP.** The server is built into Studio; the human enables it under Assistant → … → Manage MCP Servers → _Enable Studio as MCP server_, then uses Quick connect → Claude Code. With `rojo serve` running and the Rojo plugin connected:

1. `list_roblox_studios` for the `studio_id`, then `start_stop_play` to start a playtest.
2. `execute_luau` with `datamodel_type` = `Client`:
   `return require(game.Players.LocalPlayer.PlayerScripts.Client.Dev.Harness).selfTest()`
   This replays every fixture through the real Pad → Glass path and returns predictions, inference ms, frame ms and the Glass instance count.
3. `screen_capture` to look at the Glass; `get_console_output` must show no errors or warnings from our scripts.
4. `start_stop_play` to stop.

When Pad input code changes, also drag across the pad with `user_mouse_input`. Never use the MCP script-writing tools (Rule 1).

In Studio playtests, **G** or the green on-screen button toggles Draw Mode (until stations exist in M5) and **H** prints the current drawing. Avoid function keys: on a Mac they need fn held. The command bar and Studio MCP get their own copy of a required module, so Harness calls reach the running client through a BindableFunction it creates under itself.

`Dev/Harness.luau` does nothing unless `RunService:IsStudio()`. It exposes `selfTest()`, `replay(strokesBase64)`, `state()` (prediction, probabilities, model version, timings, instance counts) and `dumpStrokes()`, which prints the current drawing as base64 so the human can save it as a fixture.

## Milestones

Work in order. Finish each with its checks green and a commit; `git log` shows where things stand.

- **M0 Scaffold:** git, Rojo project with remotes, rokit tools, StyLua/selene/`.luaurc`, Lune runner with a passing smoke test, empty entry points, working `rojo build`.
- **M1 Train & export:** config, preprocess reference, training, int8 export, goldens; accuracy targets met.
- **M2 NeuralCore:** Base64, Strokes, Preprocess, Model, Explain; parity tests pass under Lune.
- **M3 Pad:** Draw Mode, camera, mouse and touch input, ink, limits, live top-3 in the HUD (no Glass yet), Dev harness.
- **M4 Glass:** builder and pools, network view, orbs, links, packets, propagation, idle state; budgets measured.
- **M5 Game loop:** world and stations, rounds, validated Submit, leaderstats, feedback.
- **M6 Polish:** lighting, sound, mobile layouts, reduced motion, a MicroProfiler pass. Then stretch goals.

## Ask the human before…

- anything that shows one player's drawing to another or stores drawings (Rule 4);
- changing the model architecture or the input pipeline beyond tuning constants;
- adding DataStores, monetization, third-party packages or HTTP;
- anything that needs their Roblox account: uploading textures or sounds (put the source files in `assets/`), publishing, Game Settings, the maturity questionnaire, testing on physical devices.
