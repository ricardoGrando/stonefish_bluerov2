#!/usr/bin/env bash
set -e

PKG="$HOME/underwater_ws/src/stonefish_bluerov2"

cp "$PKG/scenarios/bluerov2_tank_10x10.scn" "$PKG/scenarios/bluerov2_tank_10x10.scn.bak"
cp "$PKG/data/tank/wall_10x4.obj" "$PKG/data/tank/wall_10x4.obj.bak"
cp "$PKG/data/tank/floor_10x10.obj" "$PKG/data/tank/floor_10x10.obj.bak"

cat > "$PKG/data/tank/wall_10x4.obj" <<'EOF'
o wall_10x5_thick
v -5.0 -0.3 -0.5
v  5.0 -0.3 -0.5
v  5.0  0.3 -0.5
v -5.0  0.3 -0.5
v -5.0 -0.3  4.5
v  5.0 -0.3  4.5
v  5.0  0.3  4.5
v -5.0  0.3  4.5
f 1 2 3 4
f 5 8 7 6
f 1 5 6 2
f 2 6 7 3
f 3 7 8 4
f 4 8 5 1
EOF

cat > "$PKG/data/tank/floor_10x10.obj" <<'EOF'
o floor_11p2_thick
v -5.6 -5.6 -0.2
v  5.6 -5.6 -0.2
v  5.6  5.6 -0.2
v -5.6  5.6 -0.2
v -5.6 -5.6  0.2
v  5.6 -5.6  0.2
v  5.6  5.6  0.2
v -5.6  5.6  0.2
f 1 2 3 4
f 5 8 7 6
f 1 5 6 2
f 2 6 7 3
f 3 7 8 4
f 4 8 5 1
EOF

python3 - <<'PY'
from pathlib import Path
import re

p = Path.home() / "underwater_ws/src/stonefish_bluerov2/scenarios/bluerov2_tank_10x10.scn"
text = p.read_text()

repls = {
    'xyz="0.0 0.0 4.05"': 'xyz="0.0 0.0 4.2"',
    'xyz="0.0 5.0 0.0"': 'xyz="0.0 5.3 0.0"',
    'xyz="0.0 -5.0 0.0"': 'xyz="0.0 -5.3 0.0"',
    'xyz="5.0 0.0 0.0"': 'xyz="5.3 0.0 0.0"',
    'xyz="-5.0 0.0 0.0"': 'xyz="-5.3 0.0 0.0"',
}

for old, new in repls.items():
    if old not in text:
        print(f"[WARN] Did not find {old}")
    text = text.replace(old, new)

p.write_text(text)
print(f"[OK] Patched {p}")
PY

echo "[OK] Tank walls thickened and raised above the surface."
