#!/usr/bin/env bash
set -e

PKG="$HOME/underwater_ws/src/stonefish_bluerov2"

cp "$PKG/data/tank/wall_10x4.obj" "$PKG/data/tank/wall_10x4.obj.bak_overlap" 2>/dev/null || true

cat > "$PKG/data/tank/wall_10x4.obj" <<'OBJ'
o wall_11p6_thick_double_sided
v -5.8 -0.3 -0.5
v  5.8 -0.3 -0.5
v  5.8  0.3 -0.5
v -5.8  0.3 -0.5
v -5.8 -0.3  4.8
v  5.8 -0.3  4.8
v  5.8  0.3  4.8
v -5.8  0.3  4.8

# outside
f 1 2 3 4
f 5 8 7 6
f 1 5 6 2
f 2 6 7 3
f 3 7 8 4
f 4 8 5 1

# inside
f 4 3 2 1
f 6 7 8 5
f 2 6 5 1
f 3 7 6 2
f 4 8 7 3
f 1 5 8 4
OBJ

echo "[OK] Wall mesh updated with corner overlap."
