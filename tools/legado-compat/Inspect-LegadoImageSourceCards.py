from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from hypium.action.device.uidriver import UiDriver
from hypium.uidriver.by import BY


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--device-sn', required=True)
    parser.add_argument('--hdc-path', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    hdc_dir = str(Path(args.hdc_path).resolve().parent)
    os.environ['PATH'] = hdc_dir + os.pathsep + os.environ.get('PATH', '')
    driver = UiDriver.connect(device_sn=args.device_sn)
    result = {'status': 'failed', 'driver_closed': False, 'components': []}
    try:
        driver.unlock()
        driver.stop_app('com.dlzz.manxia')
        driver.wait(1)
        driver.start_app('com.dlzz.manxia', 'EntryAbility', wait_time=1)
        driver.wait_for_idle(idle_time=0.2, timeout=10)
        tab = driver.wait_for_component(BY.id('guide_main_tab_book_source'), timeout=30)
        if tab is None or not tab.isClickable():
            raise RuntimeError('BOOK_SOURCE_TAB_MISSING')
        tab.click()
        manager = driver.wait_for_component(BY.id('book_source_open_management'), timeout=30)
        if manager is None or not manager.isClickable():
            raise RuntimeError('BOOK_SOURCE_MANAGER_MISSING')
        manager.click()
        driver.wait(2)
        driver.wait_for_idle(idle_time=0.2, timeout=10)
        for component_type in ('Column', 'Row', 'Text', 'Button', 'Stack', 'Toggle'):
            for component in driver.find_all_components(BY.type(component_type))[:160]:
                try:
                    result['components'].append({
                        'type': component.getType(),
                        'id': component.getId(),
                        'key': component.getKey(),
                        'text': component.getText(),
                        'clickable': component.isClickable(),
                        'enabled': component.isEnabled(),
                        'bounds': component.getBounds(),
                    })
                except Exception:
                    continue
        result['status'] = 'passed'
    except Exception as exc:
        result['error'] = f'{type(exc).__name__}: {exc}'
    finally:
        try:
            driver.go_home()
        except Exception:
            pass
        try:
            driver.close()
            result['driver_closed'] = True
        except Exception as exc:
            result['close_error'] = f'{type(exc).__name__}: {exc}'
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    return 0 if result['status'] == 'passed' and result['driver_closed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
