#!/bin/sh
# Measures the network speed of the app on the phone with its own time logs.
# Each round starts the app cold, waits for Home, opens a title, and searches.
# The app must have sources. The result is the median of the rounds.
# Usage: scripts/measure.sh [ROUNDS]
set -e

ROUNDS=${1:-3}
LOG=/var/mobile/Library/Caches/ZettaLite/log.txt
OUT=$(mktemp -d)

for i in $(seq 1 "$ROUNDS"); do
    ssh iphone4s "killall ZettaLite 2>/dev/null; sleep 2; echo; open io.github.stivengjekaj.zettalite; sleep 30;
        uiopen 'zettalite://title?type=movie&id=tt0133093'; sleep 25;
        uiopen 'zettalite://search?q=star'; sleep 70;
        uiopen 'zettalite://tab?name=home'" >/dev/null
    # The newest launch and the lines after it.
    ssh iphone4s "cat $LOG" | awk '/ launch /{n=NR} {line[NR]=$0} END{for(i=n;i<=NR;i++) print line[i]}' >"$OUT/round$i.txt"
done

python3 -I - "$OUT" "$ROUNDS" <<'PY'
import re, statistics, sys
out, rounds = sys.argv[1], int(sys.argv[2])
def secs(t):
    h, m, s = t.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)
names = ["home first catalog", "home 2 catalogs", "manifests", "title", "search first result", "search all"]
values = {n: [] for n in names}
for r in range(1, rounds + 1):
    lines = open(f"{out}/round{r}.txt").read().splitlines()
    launch = secs(lines[0].split()[0])
    # A Home row logs "home row" when it shows. The first version logged only
    # "time catalog" when the answer came, at the same moment.
    rows = [l for l in lines if " home row " in l] or [l for l in lines if " time catalog " in l]
    catalogs = [secs(l.split()[0]) - launch for l in rows]
    if catalogs: values["home first catalog"].append(catalogs[0])
    if len(catalogs) >= 2: values["home 2 catalogs"].append(catalogs[1])
    for name, pattern in [("manifests", r"time manifests (?:\d+ of )?\d+: ([\d.]+)"), ("title", r"time meta tt0133093: ([\d.]+)"),
                          ("search first result", r"time search first result: ([\d.]+)"), ("search all", r"time search \d+ catalogs: ([\d.]+)")]:
        for l in lines:
            m = re.search(pattern, l)
            if m:
                values[name].append(float(m.group(1)))
                break
for n in names:
    v = values[n]
    text = " ".join(f"{x:.1f}" for x in v)
    print(f"{n:22} median {statistics.median(v):6.1f} s   rounds: {text}" if v else f"{n:22} no value in {rounds} rounds")
PY
