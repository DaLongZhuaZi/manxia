#!/usr/bin/env python3
"""Launch the isolated ArkWeb conformance ability through Hypium Driver."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

# Keep this standalone Driver on the repository-owned high-port policy.  The
# installed Hypium package's default 99xx range is unreliable on this host.
REPO_ROOT = Path(__file__).resolve().parents[2]
HYPium_BOOTSTRAP = REPO_ROOT / ".codex" / "skills" / "hypium-driver" / "scripts"
if str(HYPium_BOOTSTRAP) not in sys.path:
    sys.path.insert(0, str(HYPium_BOOTSTRAP))

from hypium.action.device.uidriver import UiDriver
from hypium_high_port_bootstrap import install_high_forward_port_policy


PACKAGE_NAME = "com.dlzz.manxia"
ABILITY_NAME = "LegadoArkWebConformanceAbility"


def configure_hdc(hdc_path: str) -> None:
    executable = Path(hdc_path)
    os.environ["PATH"] = str(executable.parent) + os.pathsep + os.environ.get("PATH", "")


def write_result(output_dir: Path, payload: dict[str, Any]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    result_path = output_dir / "result.json"
    result_path.write_text(json.dumps(payload, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device-sn", required=True)
    parser.add_argument("--hdc-path", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--settle-seconds", type=float, default=3.0)
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    configure_hdc(args.hdc_path)
    install_high_forward_port_policy()
    result: dict[str, Any] = {
        "status": "running",
        "device_sn": args.device_sn,
        "package": PACKAGE_NAME,
        "ability": ABILITY_NAME,
        "driver_closed": False,
    }
    driver: UiDriver | None = None
    exit_code = 1
    try:
        driver = UiDriver.connect(device_sn=args.device_sn)
        driver.unlock()
        driver.start_app(PACKAGE_NAME, ABILITY_NAME, wait_time=1)
        driver.wait_for_idle(idle_time=0.2, timeout=10)
        screenshot = output_dir / "started.jpeg"
        output_dir.mkdir(parents=True, exist_ok=True)
        driver.capture_screen(str(screenshot))
        result["screenshot"] = str(screenshot)
        result["window_bundle"] = str(driver.get_current_window().getBundleName())
        result["status"] = "started"
        time.sleep(max(0.0, args.settle_seconds))
        exit_code = 0
    except Exception as error:
        result["status"] = "failed"
        result["error"] = str(error)
    finally:
        if driver is not None:
            try:
                driver.close()
                result["driver_closed"] = True
            except Exception as error:
                result["close_error"] = str(error)
        write_result(output_dir, result)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
