python3 - <<'PY'
from pathlib import Path
import re

p = Path.home() / "underwater_ws/src/stonefish_bluerov2/scenarios/bluerov2_ros2.scn"
text = p.read_text()

for part in ["BackLeft", "BackRight", "FrontLeft", "FrontRight"]:
    text = re.sub(
        rf'(<internal_part name="{part}".*?<mass value=")([^"]+)(".*?</internal_part>)',
        rf'\g<1>0.18\3',
        text,
        flags=re.DOTALL
    )

p.write_text(text)
print("[OK] Set buoyancy box masses to 0.18")
PY
