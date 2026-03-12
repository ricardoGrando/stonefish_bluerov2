python3 - <<'PY'
from pathlib import Path
import re

base = Path.home() / "underwater_ws/src/stonefish_bluerov2"

robot = base / "scenarios/bluerov2_ros2.scn"
tank  = base / "scenarios/bluerov2_tank_10x10.scn"
bridge = base / "scripts/cmd_vel_to_thrusters.py"

text = robot.read_text()

for part in ["BackLeft", "BackRight", "FrontLeft", "FrontRight"]:
    text = re.sub(
        rf'(<internal_part name="{part}".*?<mass value=")([^"]+)(".*?</internal_part>)',
        rf'\g<1>1.8\3',
        text,
        flags=re.DOTALL
    )

robot.write_text(text)

text = tank.read_text()
text = text.replace('<arg name="position" value="0.0 0.0 1.5"/>',
                    '<arg name="position" value="0.0 0.0 2.5"/>')
tank.write_text(text)

text = bridge.read_text()
text = text.replace("self.max_command = float(self.declare_parameter('max_command', 0.65).value)",
                    "self.max_command = float(self.declare_parameter('max_command', 0.85).value)")
text = text.replace("self.surge_gain = float(self.declare_parameter('surge_gain', 0.70).value)",
                    "self.surge_gain = float(self.declare_parameter('surge_gain', 1.00).value)")
text = text.replace("self.sway_gain = float(self.declare_parameter('sway_gain', 0.70).value)",
                    "self.sway_gain = float(self.declare_parameter('sway_gain', 1.00).value)")
text = text.replace("self.heave_gain = float(self.declare_parameter('heave_gain', 0.70).value)",
                    "self.heave_gain = float(self.declare_parameter('heave_gain', 1.00).value)")
bridge.write_text(text)

print("[OK] patched buoyancy, spawn depth, and cmd_vel gains")
PY
