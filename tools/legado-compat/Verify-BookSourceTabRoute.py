#!/usr/bin/env python3
"""Verify the stable post-animation route for the main-book-source tab.

This is intentionally a low-risk Hypium Driver probe: it clicks only the
semantic book-source tab anchor and waits for a book-source-only management
control. It never imports, edits, deletes, or executes a real book source.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from hypium.action.device.uidriver import UiDriver
from hypium.uidriver.by import BY


PROJECT_ROOT = Path(__file__).resolve().parents[2]
HYPIUM_SKILL_SCRIPTS = PROJECT_ROOT / '.codex' / 'skills' / 'hypium-driver' / 'scripts'
sys.path.insert(0, str(HYPIUM_SKILL_SCRIPTS))

from hypium_high_port_bootstrap import install_high_forward_port_policy


BOOK_SOURCE_TAB_ID = 'guide_main_tab_book_source'
BOOK_SOURCE_MANAGEMENT_ID = 'book_source_open_management'
IMAGE_SOURCE_IMPORT_TEXT = '图源导入'


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument('--device-sn', required=True)
    parser.add_argument('--package', default='com.dlzz.manxia')
    parser.add_argument('--ability', default='EntryAbility')
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--settle-seconds', type=float, default=1.5)
    return parser.parse_args()


def component_is_clickable(component: object) -> bool:
    return bool(component.isEnabled() and component.isClickable())


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    result_path = output_dir / 'result.json'
    result: dict[str, object] = {
        'status': 'failed',
        'device_sn': args.device_sn,
        'package': args.package,
        'tab_id': BOOK_SOURCE_TAB_ID,
        'expected_marker_id': BOOK_SOURCE_MANAGEMENT_ID,
        'forbidden_transition_text': IMAGE_SOURCE_IMPORT_TEXT,
        'driver_closed': False,
    }
    driver: UiDriver | None = None
    try:
        install_high_forward_port_policy()
        driver = UiDriver.connect(device_sn=args.device_sn)
        driver.unlock()
        driver.start_app(args.package, args.ability, wait_time=1)
        driver.wait_for_idle(idle_time=0.2, timeout=10)
        driver.check_current_window(bundle_name=args.package)
        driver.capture_screen(str(output_dir / '01-before-click.jpeg'))

        tab = driver.wait_for_component(BY.id(BOOK_SOURCE_TAB_ID), timeout=20)
        if tab is None:
            raise RuntimeError('BOOK_SOURCE_TAB_ANCHOR_MISSING')
        if not component_is_clickable(tab):
            raise RuntimeError('BOOK_SOURCE_TAB_ANCHOR_NOT_CLICKABLE')
        tab.click()
        time.sleep(max(0.5, args.settle_seconds))
        driver.wait_for_idle(idle_time=0.2, timeout=10)

        marker = driver.wait_for_component(BY.id(BOOK_SOURCE_MANAGEMENT_ID), timeout=20)
        image_source_import = driver.find_component(BY.text(IMAGE_SOURCE_IMPORT_TEXT))
        driver.capture_screen(str(output_dir / '02-book-source-stable.jpeg'))
        result['book_source_marker_present'] = marker is not None
        result['image_source_import_present'] = image_source_import is not None
        if marker is None:
            raise RuntimeError('BOOK_SOURCE_STABLE_MARKER_MISSING')
        if image_source_import is not None:
            raise RuntimeError('BOOK_SOURCE_ROUTE_MISMATCH_IMAGE_SOURCE_VISIBLE')
        result['status'] = 'passed'
    except Exception as error:
        result['error_class'] = error.__class__.__name__
        result['error_code'] = str(error)
    finally:
        if driver is not None:
            try:
                driver.go_home()
            finally:
                driver.close()
                result['driver_closed'] = True
        result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result['status'] == 'passed' and result['driver_closed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
