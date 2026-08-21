from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device-sn", required=True)
    parser.add_argument("--hdc-path", required=True)
    args = parser.parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    sys.path.insert(0, str(repo_root / ".venv" / "Lib" / "site-packages"))
    sys.path.insert(0, str(repo_root / "tools" / "legado-compat"))
    sys.path.insert(0, str(repo_root / ".codex" / "skills" / "hypium-driver" / "scripts"))
    os.environ["PATH"] = str(Path(args.hdc_path).parent) + os.pathsep + os.environ.get("PATH", "")
    from hypium.action.device.uidriver import UiDriver
    from hypium.uidriver.by import BY
    from hypium.model.basic_data_type import UiParam
    from hypium_high_port_bootstrap import install_high_forward_port_policy

    source_id = "14DFBA9D67698EA1CD853B1F5DD7D03E544234BE8EB93692DF96E05E86AE8AFC"
    driver = None
    try:
        install_high_forward_port_policy()
        driver = UiDriver.connect(device_sn=args.device_sn, log_level="info")
        driver.unlock()
        driver.stop_app("com.dlzz.manxia")
        driver.start_app("com.dlzz.manxia", "EntryAbility", wait_time=1)
        driver.wait_for_idle(idle_time=0.2, timeout=10)
        driver.wait_for_component(BY.id("guide_main_tab_book_source"), timeout=30).click()
        driver.wait_for_component(BY.id("novel_book_source_picker_open"), timeout=30).click()
        picker_filter = driver.wait_for_component(BY.id("novel_book_source_picker_filter"), timeout=30)
        driver.clear_text(picker_filter)
        driver.input_text(picker_filter, "onehu")
        source_item = driver.wait_for_component(BY.id(f"novel_book_source_picker_item_{source_id}"), timeout=30)
        if source_item is None:
            raise RuntimeError("SOURCE_ITEM_NOT_FOUND")
        source_item.click()
        driver.wait_for_component(BY.id("novel_book_source_explore_kind_0"), timeout=45)
        driver.wait_for_component(BY.id("novel_book_source_explore_result_0"), timeout=105)
        rows = []
        for component in driver.find_all_components(BY.type("Scroll")):
            bounds = component.getBounds()
            rows.append({
                "id": component.getId(),
                "key": component.getKey(),
                "type": component.getType(),
                "scrollable": component.isScrollable(),
                "bounds": {"left": bounds.left, "top": bounds.top, "right": bounds.right, "bottom": bounds.bottom},
            })
        trace = driver.find_component(BY.id("novel_book_source_explore_v2_trace"))
        print(json.dumps({"scrolls": rows, "trace_visible": trace is not None}, ensure_ascii=False))
        return 0
    finally:
        if driver is not None:
            try:
                driver.go_home()
            except Exception:
                pass
            driver.close()


if __name__ == "__main__":
    raise SystemExit(main())
