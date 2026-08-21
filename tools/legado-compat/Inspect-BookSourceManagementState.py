#!/usr/bin/env python3
"""Capture aggregate V2 book-source management state without source data."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
HYPIUM_SKILL_SCRIPTS = PROJECT_ROOT / '.codex' / 'skills' / 'hypium-driver' / 'scripts'
sys.path.insert(0, str(HYPIUM_SKILL_SCRIPTS))

from hypium_high_port_bootstrap import install_high_forward_port_policy
from hypium.action.device.uidriver import UiDriver
from hypium.uidriver.by import BY


BOOK_SOURCE_TAB_ID = 'guide_main_tab_book_source'
BOOK_SOURCE_MANAGEMENT_ID = 'book_source_open_management'
MANAGEMENT_ROOT_ID = 'guide_novel_source_root'
TOTAL_COUNT_ID = 'novel_source_total_count'
VERIFIED_COUNT_ID = 'novel_source_v2_verified_count'
POLICY_SUMMARY_ID = 'novel_source_policy_summary'
FILTER_COUNT_ID = 'novel_source_filter_result_count'


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument('--device-sn', required=True)
    parser.add_argument('--hdc-path', required=True)
    parser.add_argument('--package', default='com.dlzz.manxia')
    parser.add_argument('--ability', default='EntryAbility')
    parser.add_argument('--output-dir', required=True)
    return parser.parse_args()


def configure_hdc(hdc_path: str) -> None:
    executable = Path(hdc_path).resolve()
    if not executable.is_file():
        raise RuntimeError(f'HDC_PATH_MISSING:{executable}')
    os.environ['PATH'] = str(executable.parent) + os.pathsep + os.environ.get('PATH', '')


def get_required_text(driver: UiDriver, component_id: str) -> str:
    component = driver.wait_for_component(BY.id(component_id), timeout=30)
    if component is None:
        raise RuntimeError(f'MANAGEMENT_MARKER_MISSING:{component_id}')
    return component.getText()


def get_optional_text(driver: UiDriver, component_id: str) -> str | None:
    component = driver.find_component(BY.id(component_id))
    if component is None:
        return None
    return component.getText()


def click_required(driver: UiDriver, component_id: str) -> None:
    component = driver.wait_for_component(BY.id(component_id), timeout=30)
    if component is None:
        raise RuntimeError(f'CLICK_TARGET_MISSING:{component_id}')
    if not component.isEnabled() or not component.isClickable():
        raise RuntimeError(f'CLICK_TARGET_NOT_CLICKABLE:{component_id}')
    component.click()


def wait_for_main_tab_or_management(driver: UiDriver, timeout_seconds: float) -> bool:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        management_root = driver.find_component(BY.id(MANAGEMENT_ROOT_ID))
        if management_root is not None:
            return True
        main_tab = driver.find_component(BY.id(BOOK_SOURCE_TAB_ID))
        if main_tab is not None:
            return False
        time.sleep(0.25)
    raise RuntimeError('MAIN_OR_MANAGEMENT_ROUTE_NOT_READY')


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    result: dict[str, object] = {
        'status': 'failed',
        'device_sn': args.device_sn,
        'package': args.package,
        'driver_closed': False,
    }
    driver: UiDriver | None = None
    try:
        configure_hdc(args.hdc_path)
        install_high_forward_port_policy()
        driver = UiDriver.connect(device_sn=args.device_sn)
        driver.unlock()
        driver.start_app(args.package, args.ability, wait_time=1)
        driver.wait_for_idle(idle_time=0.2, timeout=10)
        driver.check_current_window(bundle_name=args.package)
        already_in_management = wait_for_main_tab_or_management(driver, 30)
        result['already_in_management'] = already_in_management
        if not already_in_management:
            click_required(driver, BOOK_SOURCE_TAB_ID)
            time.sleep(1.5)
            click_required(driver, BOOK_SOURCE_MANAGEMENT_ID)
            management_root = driver.wait_for_component(BY.id(MANAGEMENT_ROOT_ID), timeout=30)
            if management_root is None:
                raise RuntimeError('MANAGEMENT_ROOT_MISSING')
        time.sleep(1.0)
        driver.wait_for_idle(idle_time=0.2, timeout=10)
        result['total_count_text'] = get_required_text(driver, TOTAL_COUNT_ID)
        result['verified_count_text'] = get_required_text(driver, VERIFIED_COUNT_ID)
        result['policy_summary_text'] = get_required_text(driver, POLICY_SUMMARY_ID)
        filter_count = get_optional_text(driver, FILTER_COUNT_ID)
        result['filter_count_visible'] = filter_count is not None
        result['filter_count_text'] = filter_count if filter_count is not None else ''
        driver.capture_screen(str(output_dir / 'book-source-management.jpeg'))
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
        (output_dir / 'result.json').write_text(
            json.dumps(result, ensure_ascii=False, indent=2),
            encoding='utf-8'
        )
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result['status'] == 'passed' and result['driver_closed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
