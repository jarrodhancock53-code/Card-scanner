# Pack Rip Tracker

A personal iPhone app that watches you open Scarlet & Violet–era Pokémon packs, identifies each card and its printing, prices it, and gives a recap of the session. Full plan: the PRD doc (decisions dated 2026-11-21).

## What is here

| Path | What it is |
| --- | --- |
| `ios/Core` | Swift package with the logic that matters: price lookup, the confidence rule, recap, CSV, card tracking, best-frame picking. Unit tested. |
| `ios/App` | SwiftUI app: camera, set picker, card list, corrections, recap, history. Recognition uses Apple Vision (no model file to train or ship). |
| `tools/sync.py` | Pulls the catalog and prices from pokemontcg.io into `data/`. |
| `tools/validate.py` | The 20-pack accuracy test and the 90% gate. |
| `data/` | Card catalog and prices per set. **Sample data until you run the sync** (see `data/README.md`). |

## Run it on your iPhone (on your Mac)

1. `brew install xcodegen`, then `cd ios && xcodegen generate && open PackRipTracker.xcodeproj`.
2. In Xcode: select the app target > Signing & Capabilities > Team = your free Apple ID. If Xcode says the bundle ID is taken, change `dev.packrip.tracker` to something unique (in `ios/project.yml`, then regenerate).
3. Plug in your iPhone, turn on Developer Mode (Settings > Privacy & Security), pick the phone, press Run.
4. A free Apple ID build stops opening after 7 days. Press Run again to reinstall.

## Get real data

```
POKEMONTCG_API_KEY=your-free-key python tools/sync.py --out data
```

Then rebuild, or host the `data/` folder and put its URL in Settings > Update data. The `Daily price sync` GitHub Action does this daily if you add the key as a repository secret.

## The accuracy test

1. Run the app on a pack; for each card note the true card id and printing in a `labels.json`.
2. Export the app's predictions in the same shape as `predictions.json` (see `tools/validate.py`).
3. `python tools/validate.py labels.json predictions.json` prints accuracy by rarity and PASS or FAIL for the gate.

## What is not proven yet

- The Swift code is compiled and tested by CI on GitHub's Mac runners, not by hand. Nothing has run on a real iPhone yet.
- Recognition thresholds (`MatchThresholds`) and the foil heuristic (`PrintingEstimator`) are starting values. Calibrate them with the accuracy test on your own packs.
- Whether pokemontcg.io returns prices for every printing is checked the first time you run the sync with a key.
