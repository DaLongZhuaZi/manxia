#!/usr/bin/env python3
"""Resolve one confirmed system dialog and verify the app regains focus."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple


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


def parse_bounds(component: object) -> Optional[Tuple[int, int, int, int]]:
    """Return (left, right, top, bottom) for a Hypium component, if readable."""
    raw_bounds = str(component.getBounds())
    match = re.fullmatch(
        r'\(left: (-?\d+), right: (-?\d+), top: (-?\d+), bottom: (-?\d+)\)',
        raw_bounds
    )
    if match is None:
        return None
    return (
        int(match.group(1)),
        int(match.group(2)),
        int(match.group(3)),
        int(match.group(4)),
    )


def contains_bounds(container: Tuple[int, int, int, int], child: Tuple[int, int, int, int]) -> bool:
    return (
        container[0] <= child[0]
        and container[1] >= child[1]
        and container[2] <= child[2]
        and container[3] >= child[3]
    )


def resolve_click_target(driver: object, text_component: object) -> Tuple[object, str]:
    """Resolve a dialog action from exact text to its unique clickable Button owner.

    System ActionMenu labels are exposed to Hypium as non-clickable Text nodes.
    Rather than clicking by coordinates or transient visual order, bind the exact
    requested label to the single enabled Button whose semantic bounds contain it.
    """
    if text_component.isEnabled() and text_component.isClickable():
        return text_component, 'exact_text_component'

    label_bounds = parse_bounds(text_component)
    if label_bounds is None:
        raise RuntimeError('Confirmed system dialog label has unreadable bounds')

    from hypium.uidriver.by import BY

    candidates: List[object] = []
    button_components = driver.find_all_components(BY.type('Button'))
    for button in button_components:
        if not button.isEnabled() or not button.isClickable():
            continue
        button_bounds = parse_bounds(button)
        if button_bounds is not None and contains_bounds(button_bounds, label_bounds):
            candidates.append(button)

    if len(candidates) != 1:
        raise RuntimeError(
            f'Confirmed system dialog label has {len(candidates)} clickable Button owners'
        )
    return candidates[0], 'exact_text_containing_button'


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device-sn', required=True)
    parser.add_argument('--hdc-path', required=True)
    parser.add_argument('--package', default='com.dlzz.manxia')
    parser.add_argument('--ability', default='EntryAbility')
    parser.add_argument('--button-text', required=True)
    parser.add_argument('--output-dir', required=True)
    parser.add_argument(
        '--post-click-component-id',
        default='',
        help=(
            'Optional stable component id that must appear after the system action has been selected. '
            'Use this to prove the app consumed the menu result rather than merely regaining focus.'
        ),
    )
    parser.add_argument(
        '--post-click-timeout',
        type=int,
        default=15,
        help='Maximum seconds to wait for --post-click-component-id after the click.',
    )
    parser.add_argument(
        '--keep-current-window',
        action='store_true',
        help='Inspect and act on the current foreground app window without launching EntryAbility.',
    )
    return parser.parse_args()


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
        'package': args.package,
        'ability': args.ability,
        'device_sn': args.device_sn,
        'button_text': args.button_text,
        'post_click_component_id': args.post_click_component_id,
        'driver_closed': False,
        'actions': [],
    }
    driver = UiDriver.connect(device_sn=args.device_sn)
    try:
        result['actions'] = ['connect']
        if not args.keep_current_window:
            driver.unlock()
            result['actions'].append('unlock')
        if args.keep_current_window:
            result['actions'].append('keep_current_window')
        else:
            driver.start_app(args.package, args.ability, wait_time=1)
            result['actions'].append('start_app')
        driver.wait_for_idle(idle_time=0.2, timeout=10)
        if args.keep_current_window:
            # A system action menu owns the foreground window while the
            # app's ExternalFileTaskAbility is waiting for an explicit user
            # choice. Do not reject that expected system-owned state before
            # querying its confirmed button.
            result['actions'].append('skip_bundle_assertion_for_system_dialog')
        else:
            driver.check_current_window(bundle_name=args.package)
            result['actions'].append('check_current_window')
        target = driver.wait_for_component(BY.text(args.button_text), timeout=30)
        if target is None:
            raise RuntimeError('Confirmed system dialog button is absent')
        click_target, selection_method = resolve_click_target(driver, target)
        result['clicked_component'] = component_record(click_target)
        result['click_selection_method'] = selection_method
        driver.capture_screen(str(output_dir / '01-before-click.jpeg'))
        # The visible label belongs to a non-clickable Text node in the
        # system ActionMenu.  Only the resolved Button owner performs the
        # action; clicking the label can return without invoking the app's
        # ActionMenu promise and therefore must never be treated as a
        # confirmed import selection.
        click_target.click()
        result['actions'].append('click_confirmed_system_dialog_button')
        driver.wait_for_idle(idle_time=0.2, timeout=10)
        driver.check_current_window(bundle_name=args.package)
        result['actions'].append('check_app_window_after_dialog')
        if args.post_click_component_id:
            post_click_component = driver.wait_for_component(
                BY.id(args.post_click_component_id),
                timeout=args.post_click_timeout,
            )
            if post_click_component is None:
                raise RuntimeError(
                    'Confirmed system dialog selection produced no required app continuation component: '
                    + args.post_click_component_id
                )
            result['post_click_component'] = component_record(post_click_component)
            result['actions'].append('verify_post_click_app_continuation')
        driver.capture_screen(str(output_dir / '02-app-restored.jpeg'))
        result['status'] = 'passed'
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
