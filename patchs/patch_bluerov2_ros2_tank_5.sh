cp ~/underwater_ws/src/stonefish_bluerov2/scenarios/bluerov2_ros2.scn \
   ~/underwater_ws/src/stonefish_bluerov2/scenarios/bluerov2_ros2.scn.bak

python3 - <<'PY'
from pathlib import Path
import re

p = Path.home() / "underwater_ws/src/stonefish_bluerov2/scenarios/bluerov2_ros2.scn"
text = p.read_text()

targets = ["FrontRight", "FrontLeft", "BackRight", "BackLeft"]

for name in targets:
    pattern = re.compile(
        rf'(<actuator name="{name}" type="thruster">.*?<thrust_model type="fluid_dynamics">\s*'
        rf'<thrust_coeff forward=")([^"]+)(" reverse=")([^"]+)("/>)',
        re.DOTALL
    )
    text, count = pattern.subn(r'\g<1>0.50\g<3>0.50\g<5>', text, count=1)
    if count != 1:
        raise RuntimeError(f"Could not patch actuator {name}")

p.write_text(text)
print(f"[OK] Patched horizontal thrusters in {p}")
PY
