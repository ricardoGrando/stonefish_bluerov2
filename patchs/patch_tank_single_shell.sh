#!/usr/bin/env bash
set -e

PKG="$HOME/underwater_ws/src/stonefish_bluerov2"
SCN="$PKG/scenarios/bluerov2_tank_10x10.scn"
OBJ="$PKG/data/tank/tank_shell.obj"

mkdir -p "$PKG/data/tank"

cp "$SCN" "$SCN.bak_shell" 2>/dev/null || true

cat > "$OBJ" <<'OBJ'
o tank_shell_open_top

# Outer bottom
v -5.8 -5.8  4.8
v  5.8 -5.8  4.8
v  5.8  5.8  4.8
v -5.8  5.8  4.8

# Outer top
v -5.8 -5.8 -0.8
v  5.8 -5.8 -0.8
v  5.8  5.8 -0.8
v -5.8  5.8 -0.8

# Inner bottom (top of tank floor)
v -5.0 -5.0  4.2
v  5.0 -5.0  4.2
v  5.0  5.0  4.2
v -5.0  5.0  4.2

# Inner top
v -5.0 -5.0 -0.8
v  5.0 -5.0 -0.8
v  5.0  5.0 -0.8
v -5.0  5.0 -0.8

# Top rim
f 5 6 14 13
f 8 16 15 7
f 5 13 16 8
f 6 7 15 14

# Inner walls
f 13 14 10 9
f 14 15 11 10
f 15 16 12 11
f 16 13 9 12

# Floor inside
f 9 10 11 12

# Outer walls
f 5 6 2 1
f 6 7 3 2
f 7 8 4 3
f 8 5 1 4

# Bottom skirt thickness
f 1 2 10 9
f 2 3 11 10
f 3 4 12 11
f 4 1 9 12

# Bottom underside
f 1 4 3 2

# Reverse faces for double sided rendering
f 13 14 6 5
f 7 15 16 8
f 8 16 13 5
f 14 15 7 6

f 9 10 14 13
f 10 11 15 14
f 11 12 16 15
f 12 9 13 16

f 12 11 10 9

f 1 2 6 5
f 2 3 7 6
f 3 4 8 7
f 4 1 5 8

f 9 10 2 1
f 10 11 3 2
f 11 12 4 3
f 12 9 1 4

f 2 3 4 1
OBJ

python3 - <<'PY'
from pathlib import Path
import re

p = Path.home() / "underwater_ws/src/stonefish_bluerov2/scenarios/bluerov2_tank_10x10.scn"
text = p.read_text()

# Make wall color lighter so the inside face is easier to see
text = re.sub(
    r'<look name="tank_wall" rgb="[^"]+" roughness="[^"]+"/>',
    '<look name="tank_wall" rgb="0.55 0.60 0.66" roughness="0.95"/>',
    text
)
text = re.sub(
    r'<look name="tank_floor" rgb="[^"]+" roughness="[^"]+"/>',
    '<look name="tank_floor" rgb="0.45 0.50 0.56" roughness="0.98"/>',
    text
)

# Replace all separate tank geometry with one shell mesh
pattern = re.compile(
    r'\s*<static name="TankFloor".*?</static>\s*'
    r'<static name="TankWallNorth".*?</static>\s*'
    r'<static name="TankWallSouth".*?</static>\s*'
    r'<static name="TankWallEast".*?</static>\s*'
    r'<static name="TankWallWest".*?</static>\s*',
    re.DOTALL
)

replacement = """
    <static name="TankShell" type="model">
        <physical>
            <mesh filename="tank/tank_shell.obj" scale="1.0"/>
            <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
        </physical>
        <visual>
            <mesh filename="tank/tank_shell.obj" scale="1.0"/>
            <origin rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
        </visual>
        <material name="Rock"/>
        <look name="tank_wall"/>
        <world_transform rpy="0.0 0.0 0.0" xyz="0.0 0.0 0.0"/>
    </static>

"""

new_text, n = pattern.subn(replacement, text, count=1)
if n != 1:
    raise SystemExit("Could not replace the old tank geometry block in the scenario.")
p.write_text(new_text)
print(f"[OK] Patched {p}")
PY

echo "[OK] Single shell tank created."
