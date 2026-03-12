cp ~/underwater_ws/src/stonefish_bluerov2/scenarios/bluerov2_ros2.scn \
   ~/underwater_ws/src/stonefish_bluerov2/scenarios/bluerov2_ros2.scn.bak

python3 - <<'PY'
from pathlib import Path
import re
import math

p = Path.home() / "underwater_ws/src/stonefish_bluerov2/scenarios/bluerov2_ros2.scn"
text = p.read_text()

pattern = re.compile(
    r'<specs thrust_coeff="([^"]+)" torque_coeff="([^"]+)" max_rpm="([^"]+)" inverted="([^"]+)"/>\s*'
    r'(<watchdog timeout="[^"]+"/>\s*)?',
    re.MULTILINE
)

def repl(m):
    thrust = m.group(1)
    torque = m.group(2)
    max_rpm = float(m.group(3))
    inverted = m.group(4).lower()
    watchdog = m.group(5) or ""

    max_setpoint = max_rpm * 2.0 * math.pi / 60.0  # rad/s

    return (
        f'<specs max_setpoint="{max_setpoint:.6f}" '
        f'inverted_setpoint="{inverted}" normalized_setpoint="true"/>\n'
        f'            {watchdog}'
        f'<rotor_dynamics type="zero_order"/>\n'
        f'            <thrust_model type="fluid_dynamics">\n'
        f'                <thrust_coeff forward="{thrust}" reverse="{thrust}"/>\n'
        f'                <torque_coeff value="{torque}"/>\n'
        f'            </thrust_model>\n'
    )

new_text, count = pattern.subn(repl, text)

if count == 0:
    raise SystemExit("No old thruster specs were found. File may already be patched.")

p.write_text(new_text)
print(f"Patched {count} thruster blocks in {p}")
PY
