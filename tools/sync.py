#!/usr/bin/env python3
"""Pull Pokemon TCG catalog + prices from pokemontcg.io into slim per-set JSON files.

Usage:
  POKEMONTCG_API_KEY=... python tools/sync.py --out data                 # all Scarlet & Violet sets
  POKEMONTCG_API_KEY=... python tools/sync.py --sets sv1,sv2 --out data
  python tools/sync.py --fixture tools/fixtures/sv_sample.json --out /tmp/data   # offline

Outputs (per set id <s>):
  <out>/catalog/<s>.json  card list: id, name, number, rarity, supertype, images
  <out>/prices/<s>.json   {"updatedAt":..., "cards": {cardId: {printing: {"market","low","high"}}}}
  <out>/sets.json         index of sets with card counts and printings seen
Printing keys are normalized to: normal, holo, reverseHolo, firstEdition.
"""
import argparse, json, os, sys, time, urllib.parse, urllib.request

API = "https://api.pokemontcg.io/v2"
PRINTING_MAP = {
    "normal": "normal", "holofoil": "holo", "reverseHolofoil": "reverseHolo",
    "1stEditionNormal": "firstEdition", "1stEditionHolofoil": "firstEdition",
    "unlimitedHolofoil": "holo", "unlimitedNormal": "normal",
}


def http_get(path, params, key):
    url = f"{API}/{path}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"X-Api-Key": key} if key else {})
    last = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except Exception as e:  # network/5xx: back off and retry
            last = e
            time.sleep(2 ** attempt)
    raise RuntimeError(f"GET {url} failed: {last}")


def fetch_sets(key, series="Scarlet & Violet"):
    data = http_get("sets", {"q": f'series:"{series}"', "pageSize": 250}, key)
    return [s["id"] for s in data["data"]]


def fetch_cards(set_id, key):
    cards, page = [], 1
    while True:
        d = http_get("cards", {"q": f"set.id:{set_id}", "page": page, "pageSize": 250}, key)
        cards += d["data"]
        if len(cards) >= d.get("totalCount", len(cards)) or not d["data"]:
            return cards
        page += 1


def slim_card(c):
    return {
        "id": c["id"], "name": c["name"], "number": c["number"],
        "rarity": c.get("rarity", ""), "supertype": c.get("supertype", ""),
        "setId": c["set"]["id"], "setName": c["set"]["name"],
        "printedTotal": c["set"].get("printedTotal"),
        "imageSmall": c.get("images", {}).get("small"),
        "imageLarge": c.get("images", {}).get("large"),
    }


def card_prices(c):
    out = {}
    for raw, entry in (c.get("tcgplayer", {}).get("prices") or {}).items():
        key = PRINTING_MAP.get(raw)
        if not key or not entry or entry.get("market") is None:
            continue
        out[key] = {"market": entry["market"], "low": entry.get("low"), "high": entry.get("high")}
    return out


def split_by_set(cards, updated_at):
    by_set = {}
    for c in cards:
        by_set.setdefault(c["set"]["id"], []).append(c)
    result = {}
    for sid, cs in by_set.items():
        cs.sort(key=lambda c: (len(c["number"]), c["number"]))
        result[sid] = (
            [slim_card(c) for c in cs],
            {"updatedAt": updated_at, "cards": {c["id"]: p for c in cs if (p := card_prices(c))}},
        )
    return result


def write(out, per_set):
    os.makedirs(f"{out}/catalog", exist_ok=True)
    os.makedirs(f"{out}/prices", exist_ok=True)
    index = []
    for sid, (cat, pr) in sorted(per_set.items()):
        json.dump(cat, open(f"{out}/catalog/{sid}.json", "w"), separators=(",", ":"))
        json.dump(pr, open(f"{out}/prices/{sid}.json", "w"), separators=(",", ":"))
        printings = sorted({p for v in pr["cards"].values() for p in v})
        index.append({"id": sid, "name": cat[0]["setName"], "cards": len(cat),
                      "printedTotal": cat[0]["printedTotal"], "priced": len(pr["cards"]),
                      "printings": printings})
    json.dump(index, open(f"{out}/sets.json", "w"), indent=1)
    return index


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data")
    ap.add_argument("--sets", help="comma-separated set ids; default: all Scarlet & Violet sets")
    ap.add_argument("--fixture", help="read a saved API response instead of calling the network")
    a = ap.parse_args(argv)
    if a.fixture:
        cards = json.load(open(a.fixture))["data"]
    else:
        key = os.environ.get("POKEMONTCG_API_KEY", "")
        sets = a.sets.split(",") if a.sets else fetch_sets(key)
        cards = [c for s in sets for c in fetch_cards(s, key)]
    updated = time.strftime("%Y-%m-%d", time.gmtime())
    index = write(a.out, split_by_set(cards, updated))
    for s in index:
        print(f"{s['id']}: {s['cards']} cards, {s['priced']} priced, printings {s['printings']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
