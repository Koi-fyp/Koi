"""Offline check that koi_pilot_heads.pt fits the Head class used by crisis_app.py (run with koivenv, needs torch).
Usage: python check_heads.py <path to koi_pilot_heads.pt> [<path to koi_pilot_results.json>]
Loads with torch.load(weights_only=False) -- the file is a pickle: only run on a file you produced yourself.
Prints: top-level keys, number of heads, seeds, parameter shapes of head 0, and a forward pass on zeros for every
modality combo (T, TA, TV, TAV). Exit 1 if load_state_dict(strict=True) fails or any output is non-finite.
With the results json: prints its top-level keys and any numeric entries whose key mentions auroc/auc/acc/f1
VERBATIM, without interpretation.
"""
import json
import sys

import torch
import torch.nn as nn


class Head(nn.Module):  # copied from crisis_app.py ("identical to the pilot cell")
    def __init__(self, dt=768, da=768, dv=2048, h=64, p=0.3):
        super().__init__()
        proj = lambda d: nn.Sequential(nn.LayerNorm(d), nn.Linear(d, h), nn.ReLU(), nn.Dropout(p))
        self.pt, self.pa, self.pv = proj(dt), proj(da), proj(dv)
        self.mlp = nn.Sequential(nn.Linear(3 * h, h), nn.ReLU(), nn.Dropout(p), nn.Linear(h, 1))

    def forward(self, t, a, v, combo):
        zt = self.pt(t)
        z0 = torch.zeros_like(zt)
        za = self.pa(a) if "A" in combo else z0
        zv = self.pv(v) if "V" in combo else z0
        return self.mlp(torch.cat([zt, za, zv], 1)).squeeze(1)


def walk(obj, path=""):
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield from walk(v, path + "/" + str(k))
    elif isinstance(obj, list):
        for i, v in enumerate(obj[:50]):
            yield from walk(v, "%s[%d]" % (path, i))
    elif isinstance(obj, (int, float)) and not isinstance(obj, bool):
        yield path, obj


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    ck = torch.load(argv[0], map_location="cpu", weights_only=False)
    print("type:", type(ck).__name__)
    if not isinstance(ck, dict) or "state_dicts" not in ck or "seeds" not in ck:
        print("PROBLEM: expected a dict with keys state_dicts and seeds; got:", list(ck)[:10] if isinstance(ck, dict) else type(ck))
        return 1
    print("keys:", list(ck.keys()))
    print("heads:", len(ck["state_dicts"]), "seeds:", ck["seeds"])
    sd0 = ck["state_dicts"][0]
    print("head 0 parameters:")
    for k, v in sd0.items():
        print("  %-28s %s" % (k, tuple(v.shape)))
    bad = 0
    for i, sd in enumerate(ck["state_dicts"]):
        m = Head()
        try:
            m.load_state_dict(sd, strict=True)
        except Exception as e:
            print("PROBLEM: head %d does not load into Head(): %s" % (i, str(e)[:300]))
            bad += 1
            continue
        m.eval()
        with torch.no_grad():
            for combo in ("T", "TA", "TV", "TAV"):
                out = m(torch.zeros(1, 768), torch.zeros(1, 768), torch.zeros(1, 2048), combo)
                if not torch.isfinite(out).all():
                    print("PROBLEM: head %d combo %s non-finite" % (i, combo))
                    bad += 1
    print("load + forward:", "FAILED" if bad else "OK for all heads and combos T/TA/TV/TAV")
    if len(argv) > 1:
        res = json.load(open(argv[1], encoding="utf-8"))
        print("results json top-level keys:", list(res.keys()) if isinstance(res, dict) else type(res).__name__)
        for path, val in walk(res):
            if any(s in path.lower() for s in ("auroc", "auc", "acc", "f1")):
                print("  %s = %s" % (path, val))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
