"""Exercise the replay CLI before credentials or networking are available."""
from pathlib import Path
import subprocess
import sys
import tempfile

exe = sys.argv[1]
with tempfile.TemporaryDirectory() as folder:
    route = Path(folder) / "route.csv"
    cases = {
        "valid": ("seconds,x,y,z,yaw\n0,1,2,3,0\n1,2,2,3,3.14\n", True),
        "header": ("time,x,y,z,yaw\n0,1,2,3,0\n1,2,2,3,0\n", False),
        "nonfinite": ("seconds,x,y,z,yaw\n0,nan,2,3,0\n1,2,2,3,0\n", False),
        "duplicate": ("seconds,x,y,z,yaw\n0,1,2,3,0\n0,2,2,3,0\n", False),
        "speed": ("seconds,x,y,z,yaw\n0,1,2,3,0\n1,32,2,3,0\n", False),
        "start": ("seconds,x,y,z,yaw\n1,1,2,3,0\n2,2,2,3,0\n", False),
        "duration": ("seconds,x,y,z,yaw\n0,1,2,3,0\n121,2,2,3,0\n", False),
        "column": ("seconds,x,y,z,yaw\n0,1,2,3,0,0\n1,2,2,3,0\n", False),
        "range": ("seconds,x,y,z,yaw\n0,1000001,2,3,0\n1,1000002,2,3,0\n", False),
        "empty": ("seconds,x,y,z,yaw\n", False),
    }
    for name, (content, valid) in cases.items():
        route.write_text(content, encoding="ascii")
        result = subprocess.run([exe, "--route", str(route), "--validate-only"],
                                capture_output=True, text=True, timeout=5)
        assert (result.returncode == 0) == valid, (name, result.stdout, result.stderr)
        assert "HELLO" not in result.stdout, "Validation must not connect"
        assert ("ROUTE_VALID" in result.stdout) == valid
    result = subprocess.run([exe, "--server", "example.org", "--validate-only"],
                            capture_output=True, text=True, timeout=5)
    assert result.returncode != 0 and "Unknown option" in result.stderr
print("player replay: bounded input and offline validation passed")
