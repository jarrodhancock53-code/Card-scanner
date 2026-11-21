# Card data

This folder is the app's card catalog and price table, one file per set.

**The files committed here are SAMPLE data** (7 cards, made from `tools/fixtures/sv_sample.json`) so the app opens and the tests run.
Replace them with real data before using the app:

```
POKEMONTCG_API_KEY=your-free-key python tools/sync.py --out data
```

The `Daily price sync` GitHub Action does the same every day once you add the key as a repository secret named `POKEMONTCG_API_KEY`.
