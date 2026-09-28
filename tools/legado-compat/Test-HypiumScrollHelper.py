#!/usr/bin/env python3
"""Deterministic regression test for Hypium virtualized-list scrolling.

The test deliberately exercises the two failure modes that previously made the
device harness unreliable: an explicit Scroll selector rejected by ArkUI and a
default semantic swipe rejected by the UI agent.  It never connects to a
device, so it is safe to run as a preflight/contract gate.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Dict, List


PROJECT_ROOT = Path(__file__).resolve().parents[2]
HELPER_PATH = PROJECT_ROOT / "tools" / "legado-compat" / "Invoke-LegadoV2HypiumNavigation.py"


class FakeComponent:
    def isEnabled(self) -> bool:
        return True

    def isClickable(self) -> bool:
        return True


class ExplicitTargetRejectingDriver:
    def __init__(self, resolve_after_default_swipes: int = 2) -> None:
        self.calls: List[Dict[str, bool]] = []
        self.resolve_after_default_swipes = resolve_after_default_swipes

    def find_component(self, selector: Any) -> Any:
        default_swipes = sum(1 for call in self.calls if not call["explicit"])
        if default_swipes >= self.resolve_after_default_swipes:
            return FakeComponent()
        return None

    def swipe(self, *args: Any, **kwargs: Any) -> None:
        explicit = "area" in kwargs
        self.calls.append({"explicit": explicit})
        if explicit:
            raise RuntimeError("explicit_scroll_rejected")

    def wait(self, seconds: float) -> None:
        del seconds


class DefaultSwipeFailingDriver:
    def __init__(self) -> None:
        self.calls = 0

    def find_component(self, selector: Any) -> Any:
        del selector
        return None

    def swipe(self, *args: Any, **kwargs: Any) -> None:
        del args, kwargs
        self.calls += 1
        raise RuntimeError("default_swipe_failed")

    def wait(self, seconds: float) -> None:
        del seconds


def load_navigation_module() -> Any:
    spec = importlib.util.spec_from_file_location("legado_hypium_navigation", HELPER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"navigation_module_unloadable:{HELPER_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run(output_path: Path) -> Dict[str, Any]:
    module = load_navigation_module()
    helper = module.wait_for_clickable_with_bounded_scroll

    explicit_driver = ExplicitTargetRejectingDriver()
    explicit_evidence: Dict[str, Any] = {}
    component = helper(
        explicit_driver,
        object(),
        "scroll_target_regression",
        2.0,
        explicit_evidence,
        scroll_target=object(),
    )
    explicit_calls = len(explicit_driver.calls)
    fallback_calls = sum(1 for call in explicit_driver.calls if not call["explicit"])
    if component is None or fallback_calls > 3:
        raise AssertionError("explicit_scroll_fallback_not_bounded")
    if int(explicit_evidence["scroll_to_target"]["fallbackMaxAttempts"]) != 3:
        raise AssertionError("fallback_budget_missing")

    default_driver = DefaultSwipeFailingDriver()
    default_evidence: Dict[str, Any] = {}
    try:
        helper(default_driver, object(), "default_scroll_regression", 1.0, default_evidence)
    except RuntimeError as error:
        if str(error) != "default_scroll_regression_MISSING":
            raise
    else:
        raise AssertionError("default_swipe_failure_not_reported")
    if default_driver.calls != 1:
        raise AssertionError(f"default_swipe_retried:{default_driver.calls}")

    result: Dict[str, Any] = {
        "status": "passed",
        "helper": "wait_for_clickable_with_bounded_scroll",
        "explicitTarget": {
            "resolved": True,
            "totalSwipes": explicit_calls,
            "fallbackSwipes": fallback_calls,
            "evidence": explicit_evidence,
        },
        "defaultTargetFailure": {
            "reportedAs": "default_scroll_regression_MISSING",
            "swipes": default_driver.calls,
            "evidence": default_evidence,
        },
        "reproductionCommand": (
            ".venv\\Scripts\\python.exe tools\\legado-compat\\Test-HypiumScrollHelper.py"
        ),
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        default=str(PROJECT_ROOT / "tools" / "legado-compat" / "evidence" / "hypium-scroll-helper-regression.json"),
    )
    args = parser.parse_args()
    try:
        result = run(Path(args.output))
    except Exception as error:
        print(json.dumps({"status": "failed", "error": f"{type(error).__name__}:{error}"}, ensure_ascii=False))
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
