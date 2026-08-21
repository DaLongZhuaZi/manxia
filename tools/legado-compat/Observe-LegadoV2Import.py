#!/usr/bin/env python3
"""Observe an already-running V2 book-source import without restarting the app."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Dict, Optional


V2_FULL_CUTOVER_ID: str = 'novel_source_policy_v2_full_cutover'
V2_POLICY_SUMMARY_ID: str = 'novel_source_policy_summary'
SOURCE_FILTER_RESULT_COUNT_ID: str = 'novel_source_filter_result_count'
SOURCE_TOTAL_COUNT_ID: str = 'novel_source_total_count'
SOURCE_FILTER_INPUT_ID: str = 'novel_source_management_filter'
SOURCE_SEARCH_TOGGLE_ID: str = 'title_action_search'
V2_VERIFIED_COUNT_ID: str = 'novel_source_v2_verified_count'
EXTERNAL_FILE_TASK_STATUS_ID: str = 'external_file_task_status'
EXTERNAL_FILE_TASK_ERROR_ID: str = 'external_file_task_error'


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device-sn', required=True)
    parser.add_argument('--hdc-path', required=True)
    parser.add_argument('--output-dir', required=True)
    parser.add_argument('--expected-count', type=int, required=True)
    parser.add_argument('--timeout', type=float, default=180.0)
    return parser.parse_args()


def configure_hdc(hdc_path: str) -> None:
    executable = Path(hdc_path)
    os.environ['PATH'] = str(executable.parent) + os.pathsep + os.environ.get('PATH', '')


def component_record(component: object) -> Dict[str, object]:
    return {
        'id': component.getId(),
        'key': component.getKey(),
        'text': component.getText(),
        'type': component.getType(),
        'enabled': component.isEnabled(),
        'clickable': component.isClickable(),
    }


def parse_source_count(text: str) -> Optional[int]:
    match = re.search(r'(\d+)', text)
    if match is None:
        return None
    return int(match.group(1))


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    result_path = output_dir / 'result.json'
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / '.codex' / 'skills' / 'hypium-driver' / 'scripts'))
    configure_hdc(args.hdc_path)
    from hypium.action.device.uidriver import UiDriver
    from hypium.uidriver.by import BY
    from hypium_high_port_bootstrap import install_high_forward_port_policy

    install_high_forward_port_policy()
    result: Dict[str, object] = {
        'status': 'failed',
        'device_sn': args.device_sn,
        'expected_count': args.expected_count,
        'driver_closed': False,
        'actions': ['connect', 'keep_current_window', 'no_unlock', 'no_start_app'],
        'observations': [],
    }
    driver = UiDriver.connect(device_sn=args.device_sn)
    try:
        deadline = time.monotonic() + args.timeout
        restored_overview: bool = False
        while time.monotonic() < deadline:
            total_count_component = driver.find_component(BY.id(SOURCE_TOTAL_COUNT_ID))
            filtered_count_component = driver.find_component(BY.id(SOURCE_FILTER_RESULT_COUNT_ID))
            filter_input_component = driver.find_component(BY.id(SOURCE_FILTER_INPUT_ID))
            search_toggle_component = driver.find_component(BY.id(SOURCE_SEARCH_TOGGLE_ID))
            count_component = total_count_component
            count_source = 'total'
            if count_component is None:
                count_component = filtered_count_component
                count_source = 'filtered_fallback'
            policy_component = driver.find_component(BY.id(V2_POLICY_SUMMARY_ID))
            cutover_component = driver.find_component(BY.id(V2_FULL_CUTOVER_ID))
            verified_component = driver.find_component(BY.id(V2_VERIFIED_COUNT_ID))
            external_status_component = driver.find_component(BY.id(EXTERNAL_FILE_TASK_STATUS_ID))
            external_error_component = driver.find_component(BY.id(EXTERNAL_FILE_TASK_ERROR_ID))
            observation: Dict[str, object] = {
                'elapsed_seconds': round(args.timeout - (deadline - time.monotonic()), 1),
                'count': component_record(count_component) if count_component is not None else None,
                'count_source': count_source if count_component is not None else 'unavailable',
                'search_filter_visible': filter_input_component is not None,
                'policy': component_record(policy_component) if policy_component is not None else None,
                'verified': component_record(verified_component) if verified_component is not None else None,
                'cutover_control_present': cutover_component is not None,
                'external_status': component_record(external_status_component)
                if external_status_component is not None else None,
                'external_error': component_record(external_error_component)
                if external_error_component is not None else None,
            }
            result['observations'].append(observation)
            if (
                total_count_component is None
                and filtered_count_component is not None
                and filter_input_component is not None
                and search_toggle_component is not None
                and not restored_overview
            ):
                if search_toggle_component.isEnabled() and search_toggle_component.isClickable():
                    search_toggle_component.click()
                    restored_overview = True
                    result['actions'].append('restore_unfiltered_management_overview')
                    driver.capture_screen(str(output_dir / 'overview-restored.jpeg'))
                    time.sleep(1.0)
                    continue
            if external_error_component is not None:
                result['external_status'] = (
                    external_status_component.getText() if external_status_component is not None else ''
                )
                result['external_error'] = external_error_component.getText()
                result['error'] = 'External file import reported a classified error'
                driver.capture_screen(str(output_dir / 'import-error.jpeg'))
                break
            if count_component is not None and count_source == 'total':
                parsed_count = parse_source_count(count_component.getText())
                if (
                    parsed_count is not None
                    and parsed_count >= args.expected_count
                ):
                    result['observed_source_count'] = parsed_count
                    result['observed_source_count_scope'] = count_source
                    if policy_component is not None:
                        result['v2_policy_summary'] = policy_component.getText()
                    result['v2_full_cutover_control_present'] = cutover_component is not None
                    result['actions'].append('verify_persisted_management_count')
                    driver.capture_screen(str(output_dir / 'import-complete.jpeg'))
                    result['status'] = 'passed'
                    break
            time.sleep(2.0)
        if result['status'] != 'passed':
            driver.capture_screen(str(output_dir / 'import-incomplete.jpeg'))
            result['error'] = 'Timed out waiting for V2 source management with expected imported count'
    except Exception as error:
        result['error'] = f'{type(error).__name__}: {error}'
        try:
            driver.capture_screen(str(output_dir / 'failure.jpeg'))
        except Exception:
            pass
    finally:
        try:
            driver.close()
            result['driver_closed'] = True
        except Exception as close_error:
            result['close_error'] = f'{type(close_error).__name__}: {close_error}'
        result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    return 0 if result['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
