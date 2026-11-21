#!/usr/bin/env python3
"""Accuracy report and gate check for the 20-pack test.

  python tools/validate.py labels.json predictions.json [--prices data/prices] [--gate 0.90] [--value-floor 5]

labels.json       [{"frame": "a.jpg", "cardId": "sv1-5", "printing": "holo", "rarity": "Special Illustration Rare", "value": 52.5}]
predictions.json  [{"frame": "a.jpg", "cardId": "sv1-5", "printing": "holo", "flagged": false}]
A prediction is correct only when card AND printing both match (the agreed gate rule).
A flagged prediction counts as "asked for a tap", not as a silent miss.
Exit code 0 when the gate passes, 1 when it fails.
"""
import argparse, json, sys

FOIL = {"holo", "reverseHolo"}


def bucket(label):
    if label["printing"] == "reverseHolo":
        return "reverse holo"
    r = label.get("rarity", "")
    if r in ("Common",):
        return "common"
    if r in ("Uncommon",):
        return "uncommon"
    if label["printing"] == "holo" and r in ("Rare", "Rare Holo", "Double Rare"):
        return "holo"
    if r:
        return "ultra rare" if r not in ("Rare",) else "rare"
    return "other"


def evaluate(labels, preds, gate=0.90, value_floor=5.0):
    p = {x["frame"]: x for x in preds}
    stats = {}
    silent_high_value = []
    totals = {"n": 0, "tap_free_correct": 0, "flagged": 0, "silent_wrong": 0, "missing": 0}

    def add(b, ok, flagged):
        s = stats.setdefault(b, {"n": 0, "correct": 0, "flagged": 0})
        s["n"] += 1
        s["correct"] += ok and not flagged
        s["flagged"] += flagged

    for lab in labels:
        pred = p.get(lab["frame"])
        b = bucket(lab)
        totals["n"] += 1
        if pred is None:
            totals["missing"] += 1
            add(b, False, False)
            continue
        flagged = bool(pred.get("flagged"))
        ok = pred["cardId"] == lab["cardId"] and pred["printing"] == lab["printing"]
        add(b, ok, flagged)
        if flagged:
            totals["flagged"] += 1
        elif ok:
            totals["tap_free_correct"] += 1
        else:
            totals["silent_wrong"] += 1
            if lab.get("value", 0) > value_floor:
                silent_high_value.append(lab["frame"])
        if lab["printing"] in FOIL:
            add("foil (gate)", ok, flagged)
    foil = stats.get("foil (gate)", {"n": 0, "correct": 0})
    foil_acc = foil["correct"] / foil["n"] if foil["n"] else 0.0
    return {
        "totals": totals,
        "by_bucket": {k: {**v, "accuracy": round(v["correct"] / v["n"], 4)} for k, v in sorted(stats.items())},
        "foil_accuracy": round(foil_acc, 4),
        "foil_n": foil["n"],
        "silent_misses_over_floor": silent_high_value,
        "gate_pass": foil["n"] > 0 and foil_acc >= gate and not silent_high_value,
        "gate": gate, "value_floor": value_floor,
    }


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("labels"); ap.add_argument("predictions")
    ap.add_argument("--gate", type=float, default=0.90)
    ap.add_argument("--value-floor", type=float, default=5.0)
    a = ap.parse_args(argv)
    rep = evaluate(json.load(open(a.labels)), json.load(open(a.predictions)), a.gate, a.value_floor)
    print(json.dumps(rep, indent=1))
    print("GATE:", "PASS" if rep["gate_pass"] else "FAIL")
    return 0 if rep["gate_pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
