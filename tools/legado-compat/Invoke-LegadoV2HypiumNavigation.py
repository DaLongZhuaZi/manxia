#!/usr/bin/env python3
"""Verify the V2 book-source management path through Hypium Driver only."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, Optional


PROJECT_ROOT = Path(__file__).resolve().parents[2]
HYPIUM_SKILL_SCRIPT_DIR = PROJECT_ROOT / ".codex" / "skills" / "hypium-driver" / "scripts"
if str(HYPIUM_SKILL_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(HYPIUM_SKILL_SCRIPT_DIR))


PACKAGE_NAME = "com.dlzz.manxia"
ABILITY_NAME = "EntryAbility"
BOOK_SOURCE_TAB_ID = "guide_main_tab_book_source"
BOOK_SOURCE_MANAGER_ID = "book_source_open_management"
BOOK_SOURCE_PICKER_OPEN_ID = "novel_book_source_picker_open"
BOOK_SOURCE_PICKER_FILTER_ID = "novel_book_source_picker_filter"
BOOK_SOURCE_PICKER_ITEM_PREFIX = "novel_book_source_picker_item_"
BOOK_SOURCE_EXPLORE_KIND_PREFIX = "novel_book_source_explore_kind_"
BOOK_SOURCE_EXPLORE_RESULT_PREFIX = "novel_book_source_explore_result_"
BOOK_SOURCE_EXPLORE_EMPTY_ID = "novel_book_source_explore_empty"
BOOK_SOURCE_EXPLORE_ERROR_ID = "novel_book_source_explore_error"
BOOK_SOURCE_EXPLORE_TRACE_ID = "novel_book_source_explore_v2_trace"
SOURCE_FILTER_ID = "novel_source_management_filter"
V2_FULL_CUTOVER_ID = "novel_source_policy_v2_full_cutover"
V2_POLICY_DETAIL_TOGGLE_ID = "novel_source_policy_detail_toggle"
V2_POLICY_DETAIL_CONTENT_ID = "novel_source_policy_detail_content"
V2_POLICY_SUMMARY_ID = "novel_source_policy_summary"
SOURCE_MANAGEMENT_EMPTY_STATE_ID = "novel_source_management_empty_message"
SOURCE_LIST_GUIDE_ID = "guide_novel_source_list"
SOURCE_FILTER_RESULT_COUNT_ID = "novel_source_filter_result_count"
SOURCE_TRACE_DETAIL_DIALOG_ID = "novel_source_trace_detail_dialog"
SOURCE_TRACE_DETAIL_CONTENT_ID = "novel_source_trace_detail_content"
SOURCE_TRACE_DETAIL_CLOSE_ID = "novel_source_trace_detail_close"
TITLE_SEARCH_ACTION_ID = "title_action_search"
SEARCH_INPUT_ID = "novel_search_keyword_input"
SEARCH_SUBMIT_ID = "novel_search_submit"
SEARCH_RESULTS_ID = "novel_search_single_source_results"
SEARCH_NO_RESULTS_ID = "novel_search_no_results_state"
SEARCH_ERROR_ID = "novel_search_error_state"
SEARCH_LOADING_ID = "novel_search_loading_state"
SEARCH_TRACE_TOGGLE_ID = "novel_search_v2_trace_toggle"
SEARCH_TRACE_DETAIL_ID = "novel_search_v2_trace_detail"
DETAIL_ROOT_ID = "novel_detail_root"
DETAIL_CHAPTER_COUNT_ID = "novel_detail_chapter_count"
DETAIL_START_READING_ID = "novel_detail_start_reading"
UNIFIED_DETAIL_ROOT_ID = "unified_detail_root"
UNIFIED_DETAIL_CHAPTER_COUNT_PORTRAIT_ID = "unified_detail_chapter_count_portrait"
UNIFIED_DETAIL_CHAPTER_COUNT_LANDSCAPE_ID = "unified_detail_chapter_count_landscape"
UNIFIED_DETAIL_START_READING_PORTRAIT_ID = "unified_detail_start_reading_portrait"
UNIFIED_DETAIL_START_READING_LANDSCAPE_ID = "unified_detail_start_reading_landscape"
UNIFIED_DETAIL_TRACE_TOGGLE_ID = "unified_detail_v2_trace_toggle"
UNIFIED_DETAIL_TRACE_DETAIL_ID = "unified_detail_v2_trace_detail"
UNIFIED_DETAIL_TRACE_EVIDENCE_ID = "unified_detail_v2_trace_evidence"
UNIFIED_DETAIL_CONTENT_DIAGNOSTICS_ID = "unified_detail_v2_content_diagnostics"
UNIFIED_DETAIL_TRACE_STORAGE_DIAGNOSTIC_ID = "unified_detail_v2_trace_storage_diagnostic"
READER_ROOT_ID = "novel_reader_root"
MANGA_READER_ROOT_IDS = ("manga_reader_root", "guide_manga_reader_root")
READER_V2_CONTENT_REFRESH_DIAGNOSTIC_ID = "novel_reader_v2_content_refresh_diagnostic"
READER_V2_CONTENT_EXECUTION_DIAGNOSTIC_ID = "novel_reader_v2_content_execution_diagnostic"
TITLE_BACK_ACTION_ID = "title_action_back"
APP_GUIDE_SKIP_BUTTON_ID = "app_guide_skip_button"
SEARCH_ERROR_TITLE = "搜索未完成"
V2_FULL_CUTOVER_BLOCKED_TEXT = "V2 全量切换已阻止该书源执行，已记录兼容性诊断"
DETAIL_TRACE_REHYDRATION_MAX_ATTEMPTS = 3
SOURCE_COMPILE_DIAGNOSTIC_CODE_PATTERN = re.compile(r"(?:INFO|WARNING|ERROR):([A-Z][A-Z0-9_]+):")
TRACE_PATTERN = re.compile(
    r"(?:最近\s+)?V2 trace[:：]([^·\r\n]+) · ([^·\r\n]+) · HTTP (\d+) · ([^·\r\n]+) · ([^\r\n]*)"
)
WEBVIEW_TIMEOUT_PATTERN = re.compile(
    r"^WEBVIEW_(?:TIMEOUT|ERROR);ownership=(?:active|queued);stage=[a-z_]+;pageBegin=\d+;"
    r"targetBegin=\d+;runtimeBegin=\d+;nonRuntimeBegin=\d+;pageEnd=\d+;"
    r"mainFrameError=\d+;(?:httpStatus=\d+|errorCode=-?\d+)$"
)
BOOK_INFO_TRACE_PATTERN = re.compile(
    r"^book_info:rules=(\d+);resolved=(\d+);selectors=.*;body=(\d+):"
    r"(empty|digest_error|[0-9a-f]{16})(?:;downloads=(\d+))?"
    r"(?:;reqTarget=(empty|digest_pending|digest_error|[0-9A-Fa-f]{64});"
    r"ua=(empty|digest_pending|digest_error|[0-9A-Fa-f]{64});"
    r"contentType=([a-z0-9.+/-]+|empty);redirects=(\d+))?"
    r"(?:;responseClass=(empty|non_html|html_access_denied|html_challenge|html_rate_limited|html_login|html_generic))?"
    r"(?:;[A-Za-z0-9_,:=.-]+)*$"
)
BOOK_INFO_FIELDS_PATTERN = re.compile(
    r"^book_info:rules=(\d+);resolved=(\d+);.*;body=(\d+):(empty|digest_error|[0-9a-f]{16})"
)
RESPONSE_CLASS_PATTERN = re.compile(
    r"(?:^|;)responseClass=(empty|non_html|html_access_denied|html_challenge|html_rate_limited|html_login|html_generic)(?:;|$)"
)
BOOK_INFO_REQUEST_EVIDENCE_PATTERN = re.compile(
    r"(?:^|;)reqMethod=(GET|POST|HEAD|SCRIPT|unknown);reqHeaderCount=(\d+);"
    r"(?:reqHeaderNames=(empty|[a-z0-9-]+(?:,[a-z0-9-]+)*);)?"
    r"reqHeaderFingerprint=(empty|digest_error|[0-9a-f]{16})(?:;|$)"
)
BOOK_INFO_TOC_URL_PATTERN = re.compile(
    r"(?:^|;)tocUrl=(empty|digest_error|[0-9a-f]{16})(?:;|$)"
)
SEARCH_TARGET_SEQUENCE_PATTERN = re.compile(
    r"(?:^|;)bookTargetSequence=(empty|(?:empty|digest_error|[0-9A-Fa-f]{64})"
    r"(?:,(?:empty|digest_error|[0-9A-Fa-f]{64})){0,7});"
    r"bookTargetSequenceDistinct=(\d+);bookTargetSequenceEmpty=(\d+)(?:;|$)"
)
SEARCH_BOOK_LIST_FINALIZATION_PATTERN = re.compile(
    r"(?:^|;)deduplicated=(\d+);reversed=(true|false)(?:;|$)"
)
BOOK_INFO_TOC_JS_TRANSCRIPT_PATTERN = re.compile(
    r"(?:^|;)tocRule=(empty|digest_error|[0-9a-f]{16});"
    r"tocVarsBefore=(empty|digest_error|[0-9a-f]{16});"
    r"tocVarsAfter=(empty|digest_error|[0-9a-f]{16})(?:;|$)"
)
BOOK_INFO_HEADERS_VARIABLE_PATTERN = re.compile(
    r"(?:^|;)headersVar=(empty|digest_error|[0-9a-f]{16})(?:;|$)"
)
BOOK_INFO_BID_VARIABLE_PATTERN = re.compile(
    r"(?:^|;)bidVar=(present|absent)(?:;|$)"
)
BOOK_INFO_NATIVE_JS_SHIM_PATTERN = re.compile(
    r"(?:^|;)nativeJsShim=(passed|failed)(?:-([01]{5}))?(?:;|$)"
)
TOC_TRACE_PATTERN = re.compile(r"^toc:(\d+)(?:;[A-Za-z0-9_,:=./-]+)*$")
TOC_COUNTS_PATTERN = re.compile(
    r"^toc:(\d+);matched=(\d+);missingUrl=(\d+);pages=(\d+);"
    r"body=(\d+):(empty|digest_error|[0-9a-f]{16});"
    r"responseClass=(empty|non_html|html_access_denied|html_challenge|html_rate_limited|html_login|html_generic)"
)
TOC_REQUEST_URL_PATTERN = re.compile(
    r"(?:^|;)reqUrl=(empty|digest_error|[0-9a-f]{16})(?:;|$)"
)
CONTENT_TRACE_PATTERN = re.compile(
    r"^content:pages=(\d+);fragments=(\d+);chars=(\d+);"
    r"replace=(applied|none);"
    r"presentation=(readable|empty|raw_html|raw_entity|invalid_image)"
    r"(?:;bridge=(available|bridge_unavailable|bridge_error|not_applicable);"
    r"bridgeChars=(\d+);bridgeDigest=(empty|digest_error|[0-9A-Fa-f]{16}))?"
    r"(?:;digest=(empty|digest_error|[0-9A-Fa-f]{16}))?(?:;[A-Za-z0-9_,:=./-]+)*$"
)
CONTENT_BRIDGE_PROBE_PATTERN = re.compile(
    r"(?:^|;)bridge=(available|bridge_unavailable|bridge_error|not_applicable);"
    r"bridgeChars=(\d+);bridgeDigest=(empty|digest_error|[0-9A-Fa-f]{16})(?:;|$)"
)
CONTENT_BRIDGE_READER_PROBE_PATTERN = re.compile(
    r"(?:^|;)bridgeReaderChars=(\d+);bridgeReaderLf=(\d+);"
    r"bridgeReaderDigest=(empty|digest_error|[0-9A-Fa-f]{16})(?:;|$)"
)
CONTENT_DIGEST_PROBE_PATTERN = re.compile(
    r"(?:^|;)digest=(empty|digest_error|[0-9A-Fa-f]{16})(?:;|$)"
)
CONTENT_STAGE_DIAGNOSTICS_PATTERN = re.compile(
    r"(?:^|;)extractChars=(\d+);extractLf=(\d+);normalizeChars=(\d+);"
    r"normalizeLf=(\d+);normalizeDelta=(-?\d+);joinedChars=(\d+);"
    r"joinedLf=(\d+);finalLf=(\d+)"
    r"(?:;firstLead=(-?\d+);firstLf=([01]);firstBlock=([01]);firstIndent=([01]))?(?:;|$)"
)
CONTENT_SCOPE_DIAGNOSTICS_PATTERN = re.compile(
    r"(?:^|;)scopeHeaders=(present|absent);scopeBid=(present|absent)(?:;|$)"
)
CONTENT_IMAGE_OUTCOME_PATTERN = re.compile(
    r"(?:^|;)imageOutcome=(image_workflow_invalid_content|image_workflow_empty_content|none)(?:;|$)"
)
CONTENT_DIAGNOSTICS_PATTERN = re.compile(
    r"^content_diag:status=(readable|empty|raw_html|raw_entity|invalid_image|unrecognized);"
    r"chars=(\d+);bridge=(available|bridge_unavailable|bridge_error|not_applicable|);"
    r"bridgeChars=(\d+);bridgeDigest=(empty|digest_error|[0-9A-Fa-f]{16}|);"
    r"digest=(empty|digest_error|[0-9A-Fa-f]{16}|);traceAt=(\d+)$"
)
TRACE_STORAGE_DIAGNOSTICS_PATTERN = re.compile(
    r"^storage:compiled=(present|missing);sourceRows=(\d+);currentRawRows=(\d+);"
    r"contentRows=(\d+);currentContentRows=(\d+);latestContentAt=(\d+);currentContentAt=(\d+)$"
)
EXPLORE_TRACE_PATTERN = re.compile(
    r"^workflow=explore;transport=(http|ark_web);http=(\d+);"
    r"error=([a-z_]+);options=(\d+);variables=(\d+);"
    r"output=([A-Za-z0-9_:=./,;-]+)$"
)
READER_V2_CONTENT_EXECUTION_PATTERN = re.compile(
    r"^state=(not_started|requesting|ready|empty|failed);"
    r"engine=(v2|legacy_or_blocked|unresolved);length=(\d+);"
    r"digest=(empty|digest_error|[0-9A-Fa-f]{16});lf=(\d+);cr=(\d+);"
    r"leadingWs=(\d+);trailingWs=(\d+);traceAt=(\d+);persisted=([01])$"
)
NETWORK_EVIDENCE_PATTERN = re.compile(
    r"(?:^|;)reqTarget=(empty|digest_pending|digest_error|[0-9A-Fa-f]{64});"
    r"ua=(empty|digest_pending|digest_error|[0-9A-Fa-f]{64});"
    r"contentType=([a-z0-9.+/-]+|empty);redirects=(\d+)(?:;|$)"
)
RESPONSE_BODY_EVIDENCE_PATTERN = re.compile(
    r"(?:^|;)body=(\d+):(empty|digest_error|[0-9A-Fa-f]{16});"
    r"responseClass=(empty|non_html|html_access_denied|html_challenge|html_rate_limited|html_login|html_generic)(?:;|$)"
)


def source_automation_token(source_id: str) -> str:
    token_parts: list[str] = []
    encoded = source_id.encode("utf-16-le")
    for index in range(0, len(encoded), 2):
        code = encoded[index] | (encoded[index + 1] << 8)
        if (48 <= code <= 57) or (65 <= code <= 90) or (97 <= code <= 122):
            token_parts.append(chr(code))
        else:
            token_parts.append(f"_{code:x}_")
    return "".join(token_parts)


def source_picker_item_id(source_id: str) -> str:
    """Source IDs are SHA-256 tokens; keep the UI selector deterministic."""
    return f"{BOOK_SOURCE_PICKER_ITEM_PREFIX}{source_id}"


def explore_kind_id(index: int) -> str:
    return f"{BOOK_SOURCE_EXPLORE_KIND_PREFIX}{index}"


def explore_result_id(index: int) -> str:
    return f"{BOOK_SOURCE_EXPLORE_RESULT_PREFIX}{index}"


def configure_hdc(hdc_path: Optional[str]) -> None:
    selected_path = hdc_path or os.environ.get("HDC_PATH")
    if not selected_path:
        return
    executable_path = Path(selected_path)
    hdc_directory = executable_path.parent if executable_path.suffix else executable_path
    os.environ["PATH"] = str(hdc_directory) + os.pathsep + os.environ.get("PATH", "")


def install_hypium_forward_port_policy() -> None:
    """Keep V2 device navigation on the repository-owned Hypium port policy."""
    from hypium_high_port_bootstrap import install_high_forward_port_policy

    install_high_forward_port_policy()


def component_record(component: Any, redact_source_identity: bool = False) -> Dict[str, Any]:
    bounds = component.getBounds()
    identifier = component.getId()
    key = component.getKey()
    if redact_source_identity:
        identifier = "redacted_source_identity"
        key = "redacted_source_identity"
    return {
        "id": identifier,
        "key": key,
        "type": component.getType(),
        "text": component.getText(),
        "enabled": component.isEnabled(),
        "clickable": component.isClickable(),
        "bounds": {
            "left": bounds.left,
            "top": bounds.top,
            "right": bounds.right,
            "bottom": bounds.bottom,
        },
    }


def reader_diagnostic_snapshot(
    driver: Any,
    by: Any,
    package: str,
    output_dir: Path,
    capture_screenshot: bool,
) -> Dict[str, Any]:
    """Capture only fixed, redacted reader observability after a failed wait."""
    snapshot: Dict[str, Any] = {
        "current_bundle": "",
        "reader_root_present": False,
        "refresh_diagnostic": {"present": False},
        "execution_diagnostic": {"present": False},
        "screenshot": None,
    }
    try:
        snapshot["current_bundle"] = current_bundle_name(driver)
    except Exception as error:
        snapshot["current_bundle_error"] = f"{type(error).__name__}: {error}"
    for key, component_id in (
        ("reader_root", READER_ROOT_ID),
        ("refresh_diagnostic", READER_V2_CONTENT_REFRESH_DIAGNOSTIC_ID),
        ("execution_diagnostic", READER_V2_CONTENT_EXECUTION_DIAGNOSTIC_ID),
    ):
        try:
            component = driver.find_component(by.id(component_id))
            if component is None:
                continue
            if key == "reader_root":
                snapshot["reader_root_present"] = True
                snapshot["reader_root"] = component_record(component)
                continue
            try:
                text_value = component.getText()
            except Exception:
                text_value = "<unreadable>"
            snapshot[key] = {
                "present": True,
                "id": component_id,
                "type": component.getType(),
                "text": text_value if isinstance(text_value, str) else "<non_text>",
            }
        except Exception as error:
            snapshot[f"{key}_error"] = f"{type(error).__name__}: {error}"
    if capture_screenshot:
        try:
            snapshot["screenshot"] = driver.capture_screen(
                str(output_dir / "reader-content-diagnostic-failure.jpeg")
            )
        except Exception as error:
            snapshot["screenshot_error"] = f"{type(error).__name__}: {error}"
    else:
        snapshot["screenshot_skipped_reason"] = "safe_read_path_or_visual_capture_disabled"
    return snapshot


def capture_image_trace_snapshot(hdc_path: Optional[str], device_sn: str) -> list[Dict[str, Any]]:
    """Read only the app's sanitized IMAGE trace channel from the device."""
    executable = hdc_path or os.environ.get("HDC_PATH") or "hdc"
    completed = subprocess.run(
        [executable, "-t", device_sn, "shell", "hilog", "-x"],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
    )
    marker = "MANXIA_LEGADO_IMAGE_TRACE:"
    events: list[Dict[str, Any]] = []
    for line in completed.stdout.splitlines():
        marker_index = line.find(marker)
        if marker_index < 0:
            continue
        payload = line[marker_index + len(marker):].strip()
        try:
            parsed = json.loads(payload)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            events.append(parsed)
    return events


def image_trace_event_key(event: Dict[str, Any]) -> str:
    """Build a value-free identity for one sanitized IMAGE trace event."""
    return "|".join(
        (
            str(event.get("traceId", "")),
            str(event.get("event", "")),
            str(event.get("attempt", "")),
            str(event.get("outcome", "")),
            str(event.get("statusCode", "")),
            str(event.get("decodeOutcome", "")),
            str(event.get("elapsedMs", "")),
        )
    )


def summarize_image_trace(events: list[Dict[str, Any]]) -> Dict[str, Any]:
    """Return a stable, redacted IMAGE-asset transport result for the runner."""
    failure_outcomes: Dict[str, int] = {}
    terminal_outcomes: Dict[str, int] = {}
    header_sets: Dict[str, int] = {}
    for event in events:
        event_name = str(event.get("event", ""))
        outcome = str(event.get("outcome", ""))
        if event_name == "transport_failure":
            failure_outcomes[outcome] = failure_outcomes.get(outcome, 0) + 1
        if event_name == "pipeline_result":
            terminal_outcomes[outcome] = terminal_outcomes.get(outcome, 0) + 1
        if event_name == "request":
            header_names = event.get("requestHeaderNames", [])
            if isinstance(header_names, list):
                normalized_names = ",".join(sorted(str(item) for item in header_names))
            else:
                normalized_names = "invalid"
            user_agent_digest = str(event.get("requestUserAgentSha256", ""))
            fingerprint = f"{normalized_names}|{user_agent_digest}"
            header_sets[fingerprint] = header_sets.get(fingerprint, 0) + 1
    return {
        "eventCount": len(events),
        "sourceRawSha256": sorted(
            {
                str(event.get("sourceRawSha256", ""))
                for event in events
                if event.get("sourceRawSha256")
            }
        ),
        "planned": sum(1 for event in events if event.get("event") == "planned"),
        "requestStarted": sum(
            1
            for event in events
            if event.get("event") == "request"
            and event.get("outcome") == "request_started"
        ),
        "httpResponses": sum(1 for event in events if event.get("event") == "http_response"),
        "decodeComplete": sum(
            1
            for event in events
            if event.get("event") == "decode" and event.get("outcome") == "decode_complete"
        ),
        "decodeFailed": sum(
            1
            for event in events
            if event.get("event") == "decode" and event.get("outcome") == "decode_failed"
        ),
        "transportFailures": sum(
            1 for event in events if event.get("event") == "transport_failure"
        ),
        "pipelineComplete": sum(
            1
            for event in events
            if event.get("event") == "pipeline_result" and event.get("outcome") == "complete"
        ),
        "pipelineFailures": sum(
            1
            for event in events
            if event.get("event") == "pipeline_result" and event.get("outcome") != "complete"
        ),
        "failureOutcomes": failure_outcomes,
        "pipelineOutcomes": terminal_outcomes,
        "requestHeaderSets": header_sets,
    }


def wait_for_clickable(driver: Any, selector: Any, label: str, timeout: float) -> Any:
    component = driver.wait_for_component(selector, timeout=timeout)
    if component is None:
        raise RuntimeError(f"{label}_MISSING")
    if not component.isEnabled():
        raise RuntimeError(f"{label}_DISABLED")
    if not component.isClickable():
        raise RuntimeError(f"{label}_NOT_CLICKABLE")
    return component


def wait_for_clickable_with_bounded_scroll(
    driver: Any,
    selector: Any,
    label: str,
    timeout: float,
    evidence: Dict[str, Any],
    scroll_target: Optional[Any] = None,
) -> Any:
    """Resolve a clickable item in a virtualized list without coordinate guesses.

    Hypium's ordinary wait only observes the current viewport.  Source cards and
    picker items can be rendered below that viewport after a filtered list
    refresh, so use short semantic swipes and re-find the stable id each time.
    The helper is deliberately bounded and leaves a structured scroll witness.
    """
    from hypium.model.basic_data_type import UiParam

    deadline = time.monotonic() + max(1.0, timeout)
    scroll_count = 0
    scroll_errors = []
    target = scroll_target
    explicit_target = target is not None
    max_scrolls = 8 if explicit_target else 24
    fallback_scrolls = 0
    evidence["scroll_to_target"] = {
        "attempts": 0,
        "maxAttempts": max_scrolls,
        "targetType": "Scroll" if target is not None else "default",
    }
    while time.monotonic() < deadline:
        component = driver.find_component(selector)
        if component is not None:
            if not component.isEnabled():
                raise RuntimeError(f"{label}_DISABLED")
            if not component.isClickable():
                raise RuntimeError(f"{label}_NOT_CLICKABLE")
            evidence["scroll_to_target"]["resolved"] = True
            evidence["scroll_to_target"]["scrolls"] = scroll_count
            return component
        if scroll_count >= max_scrolls:
            break
        try:
            if target is not None:
                driver.swipe(UiParam.UP, distance=80, area=target)
            else:
                driver.swipe(UiParam.UP, distance=80)
        except Exception as error:
            scroll_errors.append(type(error).__name__)
            if target is None:
                # A default semantic swipe already targets the device's
                # scroll surface.  Do not repeat it indefinitely after a
                # transport/UI-agent failure; record the bounded failure and
                # let the caller classify the item as missing.
                break
            # Some ArkUI containers reject an explicit Scroll selector.
            # Switch to the default semantic swipe, but bound the fallback to
            # three attempts instead of continuing through the original list
            # budget (which could otherwise cause 17 redundant swipes).
            target = None
            max_scrolls = min(max_scrolls, scroll_count + 3)
            evidence["scroll_to_target"]["maxAttempts"] = max_scrolls
            evidence["scroll_to_target"]["fallbackMaxAttempts"] = 3
            if fallback_scrolls >= 3:
                break
            try:
                driver.swipe(UiParam.UP, distance=80)
                fallback_scrolls += 1
            except Exception as fallback_error:
                scroll_errors.append(type(fallback_error).__name__)
                break
        scroll_count += 1
        evidence["scroll_to_target"]["attempts"] = scroll_count
        driver.wait(0.3)
    evidence["scroll_to_target"]["resolved"] = False
    evidence["scroll_to_target"]["scrolls"] = scroll_count
    if scroll_errors:
        evidence["scroll_to_target"]["errors"] = scroll_errors[:4]
    raise RuntimeError(f"{label}_MISSING")


def wait_for_first_component_by_id(
    driver: Any, by: Any, identifiers: tuple[str, ...], label: str, timeout: float
) -> Any:
    """Wait for either supported detail-page presentation without using UI position."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for identifier in identifiers:
            component = driver.find_component(by.id(identifier))
            if component is not None:
                return component
        driver.wait(0.4)
    raise RuntimeError(f"{label}_MISSING")


def wait_for_first_clickable_by_id(
    driver: Any, by: Any, identifiers: tuple[str, ...], label: str, timeout: float
) -> Any:
    deadline = time.monotonic() + timeout
    observed_component = False
    observed_disabled = False
    observed_not_clickable = False
    while time.monotonic() < deadline:
        for identifier in identifiers:
            component = driver.find_component(by.id(identifier))
            if component is None:
                continue
            observed_component = True
            try:
                if not component.isEnabled():
                    observed_disabled = True
                    continue
                if not component.isClickable():
                    observed_not_clickable = True
                    continue
                return component
            except Exception:
                # ArkUI can replace a Button while the TOC state commits. A
                # stale proxy is not a product-level disabled state.
                continue
        driver.wait(0.4)
    if not observed_component:
        raise RuntimeError(f"{label}_MISSING")
    if observed_disabled:
        raise RuntimeError(f"{label}_DISABLED")
    if observed_not_clickable:
        raise RuntimeError(f"{label}_NOT_CLICKABLE")
    raise RuntimeError(f"{label}_UNSTABLE")


def wait_for_positive_detail_chapter_count(driver: Any, by: Any, timeout: float) -> Optional[int]:
    """Wait for the rendered detail count after a V2 TOC trace is available."""
    deadline = time.monotonic() + timeout
    identifiers = (
        DETAIL_CHAPTER_COUNT_ID,
        UNIFIED_DETAIL_CHAPTER_COUNT_PORTRAIT_ID,
        UNIFIED_DETAIL_CHAPTER_COUNT_LANDSCAPE_ID,
    )
    while time.monotonic() < deadline:
        for identifier in identifiers:
            component = driver.find_component(by.id(identifier))
            if component is None:
                continue
            match = re.fullmatch(r"([1-9]\d*)章", str(component.getText()).strip())
            if match is not None:
                return int(match.group(1))
        driver.wait(0.4)
    return None


def wait_for_initial_route(driver: Any, by: Any, timeout: float) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if driver.find_component(by.id(V2_FULL_CUTOVER_ID)) is not None:
            return "source_management"
        if driver.find_component(by.id(BOOK_SOURCE_TAB_ID)) is not None:
            return "main_menu"
        driver.wait(0.4)
    raise RuntimeError("INITIAL_ROUTE_ANCHOR_MISSING")


def current_bundle_name(driver: Any) -> str:
    """Return the foreground bundle without retaining a window proxy."""
    window = driver.get_current_window()
    return str(window.getBundleName())


def get_text_components(driver: Any, by: Any) -> list[Any]:
    """Normalize Hypium's transient None list result during reactive updates."""
    components = driver.find_all_components(by.type("Text"))
    if components is None:
        return []
    return list(components)


def wait_for_search_outcome(
    driver: Any, by: Any, package: str, timeout: float
) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if current_bundle_name(driver) != package:
            return "app_exited"
        if driver.find_component(by.id(SEARCH_RESULTS_ID)) is not None:
            return "result"
        if driver.find_component(by.id(SEARCH_NO_RESULTS_ID)) is not None:
            return "empty"
        if driver.find_component(by.id(SEARCH_ERROR_ID)) is not None:
            return "execution_failure"
        # Production ArkUI does not expose every component id to the driver.
        # The visible error title is an explicit, stable semantic fallback.
        if driver.find_component(by.text(SEARCH_ERROR_TITLE)) is not None:
            return "execution_failure"
        text_components = get_text_components(driver, by)
        for component in text_components[:160]:
            try:
                if component.getText() == SEARCH_ERROR_TITLE:
                    return "execution_failure"
            except Exception:
                # A reactive page can replace a Text node between discovery
                # and inspection. Re-query on the next bounded poll instead
                # of treating a stale proxy as a workflow failure.
                continue
        driver.wait(0.4)
    return "ui_timeout"


def get_search_error_category(driver: Any, by: Any) -> str:
    if driver.find_component(by.text(V2_FULL_CUTOVER_BLOCKED_TEXT)) is not None:
        return "v2_full_cutover_blocked"
    text_components = get_text_components(driver, by)
    for component in text_components[:160]:
        try:
            if component.getText() == V2_FULL_CUTOVER_BLOCKED_TEXT:
                return "v2_full_cutover_blocked"
        except Exception:
            continue
    return ""


def read_source_compile_diagnostic_codes(driver: Any, by: Any, source_token: str) -> list[str]:
    """Return only compiler-generated diagnostic codes, never card text or rule data."""
    component = driver.find_component(by.id(f"novel_source_compile_diagnostic_{source_token}"))
    candidates: list[Any] = []
    if component is not None:
        candidates.append(component)
    else:
        # A few HDS virtualized cards do not publish nested Text IDs despite
        # rendering the visible label. The caller has already filtered to one
        # source card; retain only diagnostic codes from that bounded view.
        candidates = get_text_components(driver, by)[:160]
    codes: list[str] = []
    for candidate in candidates:
        try:
            text = candidate.getText()
        except Exception:
            continue
        if not isinstance(text, str) or not text.startswith("V2 编译诊断："):
            continue
        for code in SOURCE_COMPILE_DIAGNOSTIC_CODE_PATTERN.findall(text):
            if code not in codes:
                codes.append(code)
    return sorted(codes)


def wait_for_route_anchor(driver: Any, by: Any, timeout: float) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if driver.find_component(by.id(V2_FULL_CUTOVER_ID)) is not None:
            return "source_management"
        if driver.find_component(by.id(SOURCE_FILTER_ID)) is not None:
            return "source_management_filter"
        if driver.find_component(by.id(BOOK_SOURCE_TAB_ID)) is not None:
            return "main_menu"
        if driver.find_component(by.id(SEARCH_INPUT_ID)) is not None:
            return "single_source_search"
        driver.wait(0.4)
    return "missing"


def return_to_source_management(driver: Any, by: Any, timeout: float) -> str:
    back_action = wait_for_clickable(
        driver, by.id(TITLE_BACK_ACTION_ID), "SEARCH_BACK_ACTION", timeout
    )
    back_action.click()
    route = wait_for_route_anchor(driver, by, timeout)
    if route in ("source_management", "source_management_filter"):
        return route
    raise RuntimeError(f"RETURN_SOURCE_MANAGER_{route.upper()}")


def get_safe_output_summary_shape(output_summary: str) -> str:
    """Classify a trace summary without retaining its text in evidence."""
    if len(output_summary) == 0:
        return "empty"
    if output_summary.startswith("toc:"):
        return "toc_prefixed"
    if output_summary.startswith("search:"):
        return "search_prefixed"
    if output_summary.startswith("book_info:"):
        return "book_info_prefixed"
    if output_summary.startswith("transport_failed:"):
        return "transport_failure_prefixed"
    if output_summary.startswith("blocked:"):
        return "policy_blocked_prefixed"
    if re.fullmatch(r"[A-Za-z0-9_:=;.-]{1,160}", output_summary) is not None:
        return "fixed_token_grammar"
    return "nonfixed_grammar"


def get_sanitized_trace_records(
    driver: Any, by: Any, source_id: Optional[str]
) -> list[Dict[str, Any]]:
    records: list[Dict[str, Any]] = []
    text_components: list[Any] = []
    if source_id is not None:
        trace_component = driver.find_component(by.id(f"novel_source_trace_{source_id}"))
        if trace_component is not None:
            text_components.append(trace_component)
    elif hasattr(driver, "find_component"):
        # A detail page can remain in the UI tree alongside a reader or an
        # outgoing navigation layer.  Scanning every Text node in that state
        # can incorrectly join an old disclosure with a current structured
        # diagnostic. Prefer the stable non-visual evidence node: the expanded
        # disclosure itself can be virtualized when a long TOC pushes it out
        # of ArkUI's active tree. Broad text enumeration remains only the
        # search-page fallback.
        detail_trace_component = driver.find_component(
            by.id(UNIFIED_DETAIL_TRACE_EVIDENCE_ID)
        )
        if detail_trace_component is None:
            detail_trace_component = driver.find_component(
                by.id(UNIFIED_DETAIL_TRACE_DETAIL_ID)
            )
        if detail_trace_component is not None:
            text_components.append(detail_trace_component)
    if not text_components:
        text_components = get_text_components(driver, by)
    for component in text_components:
        try:
            text = component.getText()
        except Exception:
            continue
        if not isinstance(text, str):
            continue
        for match in TRACE_PATTERN.finditer(text):
            workflow = match.group(1).strip()
            output_summary = match.group(5).strip()
            output_kind = "unrecognized"
            search_match: re.Match[str] | None = None
            if output_summary.startswith("transport_failed:"):
                output_kind = "transport_failure"
            elif output_summary.startswith("blocked:"):
                output_kind = "policy_blocked"
            if workflow == "search":
                search_match = re.fullmatch(
                    r"search:(\d+)(?:;matched=(\d+);budget=(full|\d+)(?:;deduplicated=\d+;reversed=(?:true|false))?(?:;indexBase=(\d+);resolver=(html_bridge_available|string_fallback))?(?:;domReady=(loading|interactive|complete);domTable=(\d+);domTr=(\d+);domBodyChildren=(\d+);domHtmlLength=(\d+))?;bookUrlEmpty=(\d+)(?:;bookUrlRule=(?:present|missing);bookUrlRuleLength=\d+;bookUrlRuleJavaScript=(?:true|false);bookUrlRulePostfixJs=(?:true|false))?(?:;bookUrlJsResult=(\d+);bookUrlJsEmpty=(\d+);bookUrlJsError=(\d+);bookUrlJsRuntimeUnavailable=(\d+)(?:;bookUrlJsNotEvaluated=\d+;bookUrlJsMainRuleEmpty=\d+;bookUrlJsInputJson=\d+)?)?(?:;bookTargetSequence=(?:empty|(?:empty|digest_error|[0-9A-Fa-f]{64})(?:,(?:empty|digest_error|[0-9A-Fa-f]{64})){0,7});bookTargetSequenceDistinct=\d+;bookTargetSequenceEmpty=\d+)?;firstBookTarget=(empty|digest_error|[0-9A-Fa-f]{64})(?:;reqTarget=(empty|digest_pending|digest_error|[0-9A-Fa-f]{64});ua=(empty|digest_pending|digest_error|[0-9A-Fa-f]{64});contentType=([a-z0-9.+/-]+|empty);redirects=(\d+))?(?:;body=(\d+):(empty|digest_error|[0-9a-f]{16});responseClass=(empty|non_html|html_access_denied|html_challenge|html_rate_limited|html_login|html_generic);reqMethod=(GET|POST|HEAD|SCRIPT|unknown);reqHeaderCount=(\d+)(?:;reqHeaderNames=(empty|[a-z0-9-]+(?:,[a-z0-9-]+)*))?;reqHeaderFingerprint=(empty|digest_error|[0-9a-f]{16}))?)?",
                    output_summary,
                )
                if search_match is not None:
                    output_kind = (
                        "search_nonempty"
                        if int(search_match.group(1)) > 0
                        else "search_empty"
                    )
                elif output_summary.startswith("search_failed:"):
                    output_kind = "search_failure"
            records.append(
                {
                    "workflow": workflow,
                    "transport": match.group(2).strip(),
                    "statusCode": int(match.group(3)),
                    "errorCode": match.group(4).strip(),
                    "outputKind": output_kind,
                    "outputSummarySha256": hashlib.sha256(
                        output_summary.encode("utf-8")
                    ).hexdigest().upper(),
                }
            )
            if output_kind == "unrecognized":
                records[-1]["outputSummaryLength"] = len(output_summary)
                records[-1]["outputSummaryShape"] = get_safe_output_summary_shape(
                    output_summary
                )
            network_evidence = NETWORK_EVIDENCE_PATTERN.search(output_summary)
            if network_evidence is not None:
                records[-1]["requestTargetSha256"] = network_evidence.group(1).lower()
                records[-1]["requestUserAgentSha256"] = network_evidence.group(2).lower()
                records[-1]["responseContentType"] = network_evidence.group(3)
                records[-1]["redirectCount"] = int(network_evidence.group(4))
            response_body_evidence = RESPONSE_BODY_EVIDENCE_PATTERN.search(output_summary)
            if response_body_evidence is not None:
                records[-1]["responseBodyLength"] = int(response_body_evidence.group(1))
                records[-1]["responseBodyFingerprint"] = response_body_evidence.group(2).lower()
                records[-1]["responseClass"] = response_body_evidence.group(3)
            request_header_evidence = BOOK_INFO_REQUEST_EVIDENCE_PATTERN.search(output_summary)
            if request_header_evidence is not None:
                records[-1]["requestMethod"] = request_header_evidence.group(1)
                records[-1]["requestHeaderCount"] = int(request_header_evidence.group(2))
                if request_header_evidence.group(3) not in (None, "empty"):
                    records[-1]["requestHeaderNames"] = request_header_evidence.group(3).split(",")
                records[-1]["requestHeaderFingerprint"] = request_header_evidence.group(4).lower()
            book_url_rule_evidence = re.search(
                r";bookUrlRule=(present|missing);bookUrlRuleLength=(\d+);"
                r"bookUrlRuleJavaScript=(true|false);bookUrlRulePostfixJs=(true|false)",
                output_summary,
            )
            if book_url_rule_evidence is not None:
                records[-1]["bookUrlRulePresent"] = (
                    book_url_rule_evidence.group(1) == "present"
                )
                records[-1]["bookUrlRuleLength"] = int(
                    book_url_rule_evidence.group(2)
                )
                records[-1]["bookUrlRuleUsesJavaScript"] = (
                    book_url_rule_evidence.group(3) == "true"
                )
                records[-1]["bookUrlRulePostfixJavaScript"] = (
                    book_url_rule_evidence.group(4) == "true"
                )
            book_url_js_execution_evidence = re.search(
                r";bookUrlJsNotEvaluated=(\d+);bookUrlJsMainRuleEmpty=(\d+);"
                r"bookUrlJsInputJson=(\d+)",
                output_summary,
            )
            if book_url_js_execution_evidence is not None:
                records[-1]["bookUrlJsNotEvaluatedCount"] = int(
                    book_url_js_execution_evidence.group(1)
                )
                records[-1]["bookUrlJsMainRuleEmptyCount"] = int(
                    book_url_js_execution_evidence.group(2)
                )
                records[-1]["bookUrlJsInputJsonCount"] = int(
                    book_url_js_execution_evidence.group(3)
                )
            target_sequence_evidence = SEARCH_TARGET_SEQUENCE_PATTERN.search(
                output_summary
            )
            if target_sequence_evidence is not None:
                raw_sequence = target_sequence_evidence.group(1).lower()
                records[-1]["searchBookTargetSequenceSha256"] = (
                    [] if raw_sequence == "empty" else raw_sequence.split(",")
                )
                records[-1]["searchBookTargetSequenceDistinctCount"] = int(
                    target_sequence_evidence.group(2)
                )
                records[-1]["searchBookTargetSequenceEmptyCount"] = int(
                    target_sequence_evidence.group(3)
                )
            book_list_finalization = SEARCH_BOOK_LIST_FINALIZATION_PATTERN.search(
                output_summary
            )
            if book_list_finalization is not None:
                records[-1]["searchBookDeduplicatedCount"] = int(
                    book_list_finalization.group(1)
                )
                records[-1]["searchBookReversed"] = (
                    book_list_finalization.group(2) == "true"
                )
            if search_match is not None and search_match.group(2) is not None:
                records[-1]["matchedCount"] = int(search_match.group(2))
                records[-1]["resultBudget"] = search_match.group(3)
                if search_match.group(11) is not None and search_match.group(16) is not None:
                    records[-1]["emptyBookUrlCount"] = int(search_match.group(11))
                    records[-1]["firstBookTargetSha256"] = search_match.group(16).lower()
                if search_match.group(12) is not None:
                    records[-1]["bookUrlJsResultCount"] = int(search_match.group(12))
                    records[-1]["bookUrlJsEmptyCount"] = int(search_match.group(13))
                    records[-1]["bookUrlJsErrorCount"] = int(search_match.group(14))
                    records[-1]["bookUrlJsRuntimeUnavailableCount"] = int(search_match.group(15))
                if search_match.group(17) is not None:
                    records[-1]["requestTargetSha256"] = search_match.group(17).lower()
                    records[-1]["requestUserAgentSha256"] = search_match.group(18).lower()
                    records[-1]["responseContentType"] = search_match.group(19)
                    records[-1]["redirectCount"] = int(search_match.group(20))
                if search_match.group(21) is not None:
                    records[-1]["responseBodyLength"] = int(search_match.group(21))
                    records[-1]["responseBodyFingerprint"] = search_match.group(22)
                    records[-1]["responseClass"] = search_match.group(23)
                    records[-1]["requestMethod"] = search_match.group(24)
                    records[-1]["requestHeaderCount"] = int(search_match.group(25))
                    if search_match.group(26) is not None and search_match.group(26) != "empty":
                        records[-1]["requestHeaderNames"] = search_match.group(26).split(",")
                    records[-1]["requestHeaderFingerprint"] = search_match.group(27)
            book_info_match = BOOK_INFO_TRACE_PATTERN.fullmatch(output_summary)
            if workflow == "book_info" and book_info_match is not None:
                resolved_count = int(book_info_match.group(2))
                records[-1]["outputKind"] = (
                    "book_info_metadata_resolved"
                    if resolved_count > 0
                    else "book_info_metadata_empty"
                )
                records[-1]["bookInfoRuleCount"] = int(book_info_match.group(1))
                records[-1]["bookInfoResolvedCount"] = resolved_count
                records[-1]["responseBodyLength"] = int(book_info_match.group(3))
                records[-1]["responseBodyFingerprint"] = book_info_match.group(4)
                if book_info_match.group(5) is not None:
                    records[-1]["downloadCount"] = int(book_info_match.group(5))
                if book_info_match.group(6) is not None:
                    records[-1]["requestTargetSha256"] = book_info_match.group(6).lower()
                    records[-1]["requestUserAgentSha256"] = book_info_match.group(7).lower()
                    records[-1]["responseContentType"] = book_info_match.group(8)
                    records[-1]["redirectCount"] = int(book_info_match.group(9))
                if book_info_match.group(10) is not None:
                    records[-1]["responseClass"] = book_info_match.group(10)
            elif workflow == "book_info":
                book_info_fields = BOOK_INFO_FIELDS_PATTERN.search(output_summary)
                response_class = RESPONSE_CLASS_PATTERN.search(output_summary)
                if book_info_fields is not None:
                    resolved_count = int(book_info_fields.group(2))
                    records[-1]["outputKind"] = (
                        "book_info_metadata_resolved"
                        if resolved_count > 0
                        else "book_info_metadata_empty"
                    )
                    records[-1]["bookInfoRuleCount"] = int(book_info_fields.group(1))
                    records[-1]["bookInfoResolvedCount"] = resolved_count
                    records[-1]["responseBodyLength"] = int(book_info_fields.group(3))
                    records[-1]["responseBodyFingerprint"] = book_info_fields.group(4)
                if response_class is not None:
                    records[-1]["responseClass"] = response_class.group(1)
            if workflow == "book_info":
                toc_url_evidence = BOOK_INFO_TOC_URL_PATTERN.search(output_summary)
                if toc_url_evidence is not None:
                    records[-1]["bookInfoTocUrlFingerprint"] = toc_url_evidence.group(1)
                toc_js_transcript = BOOK_INFO_TOC_JS_TRANSCRIPT_PATTERN.search(output_summary)
                if toc_js_transcript is not None:
                    records[-1]["bookInfoTocRuleFingerprint"] = toc_js_transcript.group(1)
                    records[-1]["bookInfoTocVariablesBeforeFingerprint"] = toc_js_transcript.group(2)
                    records[-1]["bookInfoTocVariablesAfterFingerprint"] = toc_js_transcript.group(3)
                headers_variable_evidence = BOOK_INFO_HEADERS_VARIABLE_PATTERN.search(output_summary)
                if headers_variable_evidence is not None:
                    records[-1]["bookInfoHeadersVariableFingerprint"] = headers_variable_evidence.group(1)
                bid_variable_evidence = BOOK_INFO_BID_VARIABLE_PATTERN.search(output_summary)
                if bid_variable_evidence is not None:
                    records[-1]["bookInfoBidVariableState"] = bid_variable_evidence.group(1)
                native_js_shim_evidence = BOOK_INFO_NATIVE_JS_SHIM_PATTERN.search(output_summary)
                if native_js_shim_evidence is not None:
                    records[-1]["nativeJsShimStatus"] = native_js_shim_evidence.group(1)
                    records[-1]["nativeJsShimDetail"] = native_js_shim_evidence.group(2) or ""
                request_evidence = BOOK_INFO_REQUEST_EVIDENCE_PATTERN.search(output_summary)
                if request_evidence is not None:
                    records[-1]["requestMethod"] = request_evidence.group(1)
                    records[-1]["requestHeaderCount"] = int(request_evidence.group(2))
                    if request_evidence.group(3) not in (None, "empty"):
                        records[-1]["requestHeaderNames"] = request_evidence.group(3).split(",")
                    records[-1]["requestHeaderFingerprint"] = request_evidence.group(4).lower()
            toc_match = TOC_TRACE_PATTERN.fullmatch(output_summary)
            if workflow == "toc" and toc_match is not None:
                records[-1]["outputKind"] = (
                    "toc_nonempty" if int(toc_match.group(1)) > 0 else "toc_empty"
                )
                records[-1]["chapterCount"] = int(toc_match.group(1))
                toc_counts = TOC_COUNTS_PATTERN.match(output_summary)
                if toc_counts is not None:
                    records[-1]["tocMatchedElementCount"] = int(toc_counts.group(2))
                    records[-1]["tocMissingChapterUrlCount"] = int(toc_counts.group(3))
                    records[-1]["tocPageCount"] = int(toc_counts.group(4))
                    records[-1]["responseBodyLength"] = int(toc_counts.group(5))
                    records[-1]["responseBodyFingerprint"] = toc_counts.group(6)
                    records[-1]["responseClass"] = toc_counts.group(7)
                request_url_evidence = TOC_REQUEST_URL_PATTERN.search(output_summary)
                if request_url_evidence is not None:
                    records[-1]["requestUrlFingerprint"] = request_url_evidence.group(1)
            elif workflow == "toc" and output_summary == "toc_rule_exception":
                # The application deliberately reduces analyzer exceptions to
                # this fixed token before a device trace leaves memory.
                records[-1]["outputKind"] = "toc_rule_exception"
            content_match = CONTENT_TRACE_PATTERN.fullmatch(output_summary)
            if workflow == "content" and content_match is not None:
                characters = int(content_match.group(3))
                presentation = content_match.group(5)
                records[-1]["outputKind"] = (
                    "content_invalid_image"
                    if presentation == "invalid_image"
                    else ("content_readable" if characters > 0 and presentation == "readable" else "content_not_readable")
                )
                records[-1]["contentPageCount"] = int(content_match.group(1))
                records[-1]["contentFragmentCount"] = int(content_match.group(2))
                records[-1]["contentCharacterCount"] = characters
                records[-1]["contentReplaceStatus"] = content_match.group(4)
                records[-1]["contentPresentation"] = presentation
                image_outcome = CONTENT_IMAGE_OUTCOME_PATTERN.search(output_summary)
                if image_outcome is not None:
                    records[-1]["imageWorkflowOutcome"] = image_outcome.group(1)
                stage_diagnostics = CONTENT_STAGE_DIAGNOSTICS_PATTERN.search(output_summary)
                if stage_diagnostics is not None:
                    records[-1]["contentStageDiagnosticsSource"] = "output_summary"
                    records[-1]["contentExtractedCharacterCount"] = int(stage_diagnostics.group(1))
                    records[-1]["contentExtractedLineFeedCount"] = int(stage_diagnostics.group(2))
                    records[-1]["contentNormalizedCharacterCount"] = int(stage_diagnostics.group(3))
                    records[-1]["contentNormalizedLineFeedCount"] = int(stage_diagnostics.group(4))
                    records[-1]["contentNormalizationDelta"] = int(stage_diagnostics.group(5))
                    records[-1]["contentJoinedCharacterCount"] = int(stage_diagnostics.group(6))
                    records[-1]["contentJoinedLineFeedCount"] = int(stage_diagnostics.group(7))
                    records[-1]["contentFinalLineFeedCount"] = int(stage_diagnostics.group(8))
                    if stage_diagnostics.group(9) is not None:
                        records[-1]["contentFirstExtractLeadingWhitespaceCount"] = int(stage_diagnostics.group(9))
                        records[-1]["contentFirstExtractStartsWithLineFeed"] = int(stage_diagnostics.group(10))
                        records[-1]["contentFirstExtractStartsWithBlockTag"] = int(stage_diagnostics.group(11))
                        records[-1]["contentFirstNormalizeStartsWithReaderIndent"] = int(stage_diagnostics.group(12))
                scope_diagnostics = CONTENT_SCOPE_DIAGNOSTICS_PATTERN.search(output_summary)
                if scope_diagnostics is not None:
                    records[-1]["contentScopeHeaders"] = scope_diagnostics.group(1)
                    records[-1]["contentScopeBid"] = scope_diagnostics.group(2)
                if content_match.group(6) is not None:
                    records[-1]["contentBridgeStatus"] = content_match.group(6)
                    records[-1]["contentBridgeCharacterCount"] = int(content_match.group(7))
                    records[-1]["contentBridgeFingerprint"] = content_match.group(8)
                if content_match.group(9) is not None:
                    records[-1]["contentFingerprint"] = content_match.group(9)
                bridge_reader_probe = CONTENT_BRIDGE_READER_PROBE_PATTERN.search(
                    output_summary
                )
                if bridge_reader_probe is not None:
                    records[-1]["contentBridgeReaderCharacterCount"] = int(
                        bridge_reader_probe.group(1)
                    )
                    records[-1]["contentBridgeReaderLineFeedCount"] = int(
                        bridge_reader_probe.group(2)
                    )
                    records[-1]["contentBridgeReaderFingerprint"] = (
                        bridge_reader_probe.group(3).lower()
                    )
                content_digest_probe = CONTENT_DIGEST_PROBE_PATTERN.search(
                    output_summary
                )
                if content_digest_probe is not None:
                    records[-1]["contentFingerprint"] = (
                        content_digest_probe.group(1)
                    )
            timeout_index = output_summary.find("WEBVIEW_TIMEOUT;")
            error_index = output_summary.find("WEBVIEW_ERROR;")
            lifecycle_index = timeout_index if timeout_index >= 0 else error_index
            if lifecycle_index >= 0:
                lifecycle = output_summary[lifecycle_index:].strip()
                if WEBVIEW_TIMEOUT_PATTERN.fullmatch(lifecycle) is not None:
                    records[-1]["webViewLifecycle"] = lifecycle
    return records


def apply_structured_content_diagnostics(driver: Any, by: Any, records: list[Dict[str, Any]]) -> None:
    """Attach the fixed app-side content DTO without retaining any page text."""
    component = driver.find_component(by.id(UNIFIED_DETAIL_CONTENT_DIAGNOSTICS_ID))
    if component is None:
        return
    try:
        text = component.getText()
    except Exception:
        return
    if not isinstance(text, str):
        return
    match = CONTENT_DIAGNOSTICS_PATTERN.fullmatch(text)
    if match is None:
        raise RuntimeError("CONTENT_DIAGNOSTICS_GRAMMAR_INVALID")
    for record in records:
        if record.get("workflow") == "content":
            record["contentDiagnosticsSource"] = "persisted_summary"
            record["contentPresentation"] = match.group(1)
            record["contentCharacterCount"] = int(match.group(2))
            record["contentBridgeStatus"] = match.group(3)
            record["contentBridgeCharacterCount"] = int(match.group(4))
            record["contentBridgeFingerprint"] = match.group(5).lower()
            record["contentFingerprint"] = match.group(6).lower()
            record["traceOccurredAt"] = int(match.group(7))
            return


def read_storage_diagnostic(driver: Any, by: Any) -> str:
    component = driver.find_component(by.id(UNIFIED_DETAIL_TRACE_STORAGE_DIAGNOSTIC_ID))
    if component is None:
        return ""
    try:
        text = component.getText()
    except Exception:
        return ""
    if not isinstance(text, str) or TRACE_STORAGE_DIAGNOSTICS_PATTERN.fullmatch(text) is None:
        raise RuntimeError("TRACE_STORAGE_DIAGNOSTICS_GRAMMAR_INVALID")
    return text


def run_trace_parser_contract() -> Dict[str, Any]:
    """Exercise the response-class parser without loading Hypium or a source."""

    explore_failure = parse_explore_trace_text(
        "workflow=explore;transport=ark_web;http=0;error=network;"
        "options=1;variables=0;output=explore-kinds:failed:network"
    )
    if (
        explore_failure.get("workflow") != "explore"
        or explore_failure.get("transport") != "ark_web"
        or explore_failure.get("statusCode") != 0
        or explore_failure.get("errorCode") != "network"
        or explore_failure.get("optionCount") != 1
        or explore_failure.get("variableCount") != 0
        or explore_failure.get("outputSummary") != "explore-kinds:failed:network"
    ):
        raise RuntimeError("TRACE_PARSER_CONTRACT_EXPLORE_NETWORK_FAILURE")

    class FixedTraceComponent:
        def getText(self) -> str:
            return (
                "V2 trace：book_info · http · HTTP 403 · http · "
                "book_info:rules=6;resolved=0;selectors=transport_unavailable;"
                "body=263:9fc78f13abf4e9ec;responseClass=html_access_denied;tocUrl=empty;"
                "bidVar=present;"
                "reqMethod=GET;reqHeaderCount=5;reqHeaderNames=accept-encoding,cache-control,connection,keep-alive,user-agent;reqHeaderFingerprint=da8c1b90e9f4d06f\n"
                "V2 trace：toc · http · HTTP 200 · rule · toc_rule_exception\n"
                "V2 trace：toc · http · HTTP 200 · none · toc:0;matched=0;missingUrl=0;pages=1;"
                "body=1332:89f55dc8a0acb798;responseClass=non_html;reqUrl=89f55dc8a0acb798;"
                "reqTarget=digest_pending;ua=empty;contentType=text/html;redirects=0\n"
                "V2 trace：search · http · HTTP 200 · none · search:1;matched=1;budget=100;"
                "deduplicated=0;reversed=false;"
                "bookUrlEmpty=0;bookUrlRule=present;bookUrlRuleLength=42;bookUrlRuleJavaScript=true;bookUrlRulePostfixJs=true;"
                "bookUrlJsResult=1;bookUrlJsEmpty=0;bookUrlJsError=0;bookUrlJsRuntimeUnavailable=0;"
                "bookUrlJsNotEvaluated=0;bookUrlJsMainRuleEmpty=0;bookUrlJsInputJson=1;"
                "bookTargetSequence=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;"
                "bookTargetSequenceDistinct=1;bookTargetSequenceEmpty=0;"
                "firstBookTarget=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;"
                "reqTarget=abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd;"
                "ua=empty;contentType=text/html;redirects=0;body=177:ad9429d955840927;"
                "responseClass=html_generic;reqMethod=GET;reqHeaderCount=5;"
                "reqHeaderNames=accept-encoding,cache-control,connection,keep-alive,user-agent;reqHeaderFingerprint=da8c1b90e9f4d06f\n"
                "V2 trace：content · http · HTTP 200 · none · "
                "content:pages=1;fragments=3;chars=289;replace=none;presentation=readable;"
                "bridge=available;bridgeChars=233;bridgeDigest=8A95CF5A50720C2E;"
                "bridgeReaderChars=289;bridgeReaderLf=2;bridgeReaderDigest=4ECF035148AE046D;"
                "digest=4ECF035148AE046D;"
                "extractChars=233;extractLf=2;normalizeChars=289;normalizeLf=2;normalizeDelta=56;"
                "joinedChars=289;joinedLf=2;finalLf=2;firstLead=0;firstLf=0;firstBlock=1;firstIndent=1;"
                "reqTarget=feedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedface;"
                "ua=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;"
                "contentType=text/html;redirects=0;body=512:0123456789abcdef;responseClass=html_generic;"
                "reqMethod=GET;reqHeaderCount=4;reqHeaderNames=cache-control,connection,keep-alive,user-agent;reqHeaderFingerprint=fedcba9876543210"
            )

    class FixedTraceBy:
        def type(self, component_type: str) -> str:
            return component_type

    class FixedTraceDriver:
        def find_all_components(self, component_type: str) -> list[FixedTraceComponent]:
            return [FixedTraceComponent()]

    class EmptyTraceDriver:
        def find_all_components(self, component_type: str) -> None:
            return None

    records = get_sanitized_trace_records(
        FixedTraceDriver(), FixedTraceBy(), None
    )
    if len(records) != 5:
        raise RuntimeError("TRACE_PARSER_CONTRACT_RECORD_COUNT")
    if get_text_components(EmptyTraceDriver(), FixedTraceBy()):
        raise RuntimeError("TRACE_PARSER_CONTRACT_EMPTY_COMPONENTS")
    record = records[0]
    if (
        record.get("workflow") != "book_info"
        or record.get("statusCode") != 403
        or record.get("errorCode") != "http"
        or record.get("outputKind") != "book_info_metadata_empty"
        or record.get("bookInfoRuleCount") != 6
        or record.get("bookInfoResolvedCount") != 0
        or record.get("responseBodyLength") != 263
        or record.get("responseBodyFingerprint") != "9fc78f13abf4e9ec"
        or record.get("responseClass") != "html_access_denied"
        or record.get("bookInfoTocUrlFingerprint") != "empty"
        or record.get("bookInfoBidVariableState") != "present"
        or record.get("requestMethod") != "GET"
        or record.get("requestHeaderCount") != 5
        or record.get("requestHeaderNames") != ["accept-encoding", "cache-control", "connection", "keep-alive", "user-agent"]
        or record.get("requestHeaderFingerprint") != "da8c1b90e9f4d06f"
    ):
        raise RuntimeError("TRACE_PARSER_CONTRACT_FIELDS")
    toc_record = records[1]
    if (
        toc_record.get("workflow") != "toc"
        or toc_record.get("statusCode") != 200
        or toc_record.get("errorCode") != "rule"
        or toc_record.get("outputKind") != "toc_rule_exception"
    ):
        raise RuntimeError("TRACE_PARSER_CONTRACT_TOC_RULE_EXCEPTION")
    if get_safe_output_summary_shape("toc:0") != "toc_prefixed":
        raise RuntimeError("TRACE_PARSER_CONTRACT_SAFE_TOC_SHAPE")
    if get_safe_output_summary_shape("") != "empty":
        raise RuntimeError("TRACE_PARSER_CONTRACT_SAFE_EMPTY_SHAPE")
    toc_empty_record = records[2]
    if (
        toc_empty_record.get("outputKind") != "toc_empty"
        or toc_empty_record.get("chapterCount") != 0
        or toc_empty_record.get("tocMatchedElementCount") != 0
        or toc_empty_record.get("tocMissingChapterUrlCount") != 0
        or toc_empty_record.get("tocPageCount") != 1
        or toc_empty_record.get("responseBodyLength") != 1332
        or toc_empty_record.get("responseBodyFingerprint") != "89f55dc8a0acb798"
        or toc_empty_record.get("requestUrlFingerprint") != "89f55dc8a0acb798"
        or toc_empty_record.get("requestTargetSha256") != "digest_pending"
        or toc_empty_record.get("responseContentType") != "text/html"
        or toc_empty_record.get("redirectCount") != 0
    ):
        raise RuntimeError("TRACE_PARSER_CONTRACT_TOC_NETWORK_SUFFIX")
    search_record = records[3]
    if (
        search_record.get("outputKind") != "search_nonempty"
        or search_record.get("matchedCount") != 1
        or search_record.get("searchBookDeduplicatedCount") != 0
        or search_record.get("searchBookReversed") is not False
        or search_record.get("emptyBookUrlCount") != 0
        or search_record.get("bookUrlRulePresent") is not True
        or search_record.get("bookUrlRuleLength") != 42
        or search_record.get("bookUrlRuleUsesJavaScript") is not True
        or search_record.get("bookUrlRulePostfixJavaScript") is not True
        or search_record.get("bookUrlJsNotEvaluatedCount") != 0
        or search_record.get("bookUrlJsMainRuleEmptyCount") != 0
        or search_record.get("bookUrlJsInputJsonCount") != 1
        or search_record.get("bookUrlJsResultCount") != 1
        or search_record.get("bookUrlJsEmptyCount") != 0
        or search_record.get("bookUrlJsErrorCount") != 0
        or search_record.get("bookUrlJsRuntimeUnavailableCount") != 0
        or search_record.get("searchBookTargetSequenceSha256")
        != ["0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"]
        or search_record.get("searchBookTargetSequenceDistinctCount") != 1
        or search_record.get("searchBookTargetSequenceEmptyCount") != 0
        or search_record.get("firstBookTargetSha256")
        != "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        or search_record.get("requestTargetSha256")
        != "abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd"
        or search_record.get("responseContentType") != "text/html"
        or search_record.get("responseBodyLength") != 177
        or search_record.get("responseBodyFingerprint") != "ad9429d955840927"
        or search_record.get("responseClass") != "html_generic"
        or search_record.get("requestMethod") != "GET"
        or search_record.get("requestHeaderCount") != 5
        or search_record.get("requestHeaderNames") != ["accept-encoding", "cache-control", "connection", "keep-alive", "user-agent"]
        or search_record.get("requestHeaderFingerprint") != "da8c1b90e9f4d06f"
    ):
        raise RuntimeError("TRACE_PARSER_CONTRACT_SEARCH_TARGET")
    content_record = records[4]
    if (
        content_record.get("outputKind") != "content_readable"
        or content_record.get("contentPageCount") != 1
        or content_record.get("contentFragmentCount") != 3
        or content_record.get("contentCharacterCount") != 289
        or content_record.get("contentReplaceStatus") != "none"
        or content_record.get("contentPresentation") != "readable"
        or content_record.get("contentFingerprint") != "4ECF035148AE046D"
        or content_record.get("contentBridgeStatus") != "available"
        or content_record.get("contentBridgeCharacterCount") != 233
        or content_record.get("contentBridgeFingerprint") != "8A95CF5A50720C2E"
        or content_record.get("contentBridgeReaderCharacterCount") != 289
        or content_record.get("contentBridgeReaderLineFeedCount") != 2
        or content_record.get("contentBridgeReaderFingerprint") != "4ecf035148ae046d"
        or content_record.get("contentStageDiagnosticsSource") != "output_summary"
        or content_record.get("contentExtractedCharacterCount") != 233
        or content_record.get("contentExtractedLineFeedCount") != 2
        or content_record.get("contentNormalizedCharacterCount") != 289
        or content_record.get("contentNormalizedLineFeedCount") != 2
        or content_record.get("contentNormalizationDelta") != 56
        or content_record.get("contentJoinedCharacterCount") != 289
        or content_record.get("contentJoinedLineFeedCount") != 2
        or content_record.get("contentFinalLineFeedCount") != 2
        or content_record.get("contentFirstExtractLeadingWhitespaceCount") != 0
        or content_record.get("contentFirstExtractStartsWithLineFeed") != 0
        or content_record.get("contentFirstExtractStartsWithBlockTag") != 1
        or content_record.get("contentFirstNormalizeStartsWithReaderIndent") != 1
        or content_record.get("requestTargetSha256")
        != "feedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedface"
        or content_record.get("requestUserAgentSha256")
        != "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        or content_record.get("responseContentType") != "text/html"
        or content_record.get("redirectCount") != 0
        or content_record.get("responseBodyLength") != 512
        or content_record.get("responseBodyFingerprint") != "0123456789abcdef"
        or content_record.get("responseClass") != "html_generic"
        or content_record.get("requestMethod") != "GET"
        or content_record.get("requestHeaderCount") != 4
        or content_record.get("requestHeaderNames") != ["cache-control", "connection", "keep-alive", "user-agent"]
        or content_record.get("requestHeaderFingerprint") != "fedcba9876543210"
    ):
        raise RuntimeError("TRACE_PARSER_CONTRACT_CONTENT")
    return {
        "status": "passed",
        "contract": "sanitized_workflow_trace_classification",
        "assertions": 46,
        "responseClass": "html_access_denied",
        "tocOutputKind": "toc_rule_exception",
    }


def reader_root_ids_for_workflow(image_workflow: bool) -> tuple[str, ...]:
    return MANGA_READER_ROOT_IDS if image_workflow else (READER_ROOT_ID,)


def has_required_image_pipeline_result(events: list[Dict[str, Any]]) -> bool:
    return any(event.get("event") == "pipeline_result" for event in events)


def run_image_explore_harness_contract() -> Dict[str, Any]:
    """Verify IMAGE routing invariants without loading Hypium or a device."""

    image_root_ids = reader_root_ids_for_workflow(True)
    if READER_ROOT_ID in image_root_ids:
        raise RuntimeError("IMAGE_EXPLORE_CONTRACT_ACCEPTED_NOVEL_READER")
    for reader_root_id in MANGA_READER_ROOT_IDS:
        if reader_root_id not in image_root_ids:
            raise RuntimeError("IMAGE_EXPLORE_CONTRACT_MANGA_READER_MISSING")
    if not has_required_image_pipeline_result([{"event": "pipeline_result"}]):
        raise RuntimeError("IMAGE_EXPLORE_CONTRACT_PIPELINE_RESULT_REJECTED")
    if has_required_image_pipeline_result([{"event": "request_started"}]):
        raise RuntimeError("IMAGE_EXPLORE_CONTRACT_NONTERMINAL_TRACE_ACCEPTED")
    return {
        "status": "passed",
        "contract": "image_explore_routes_to_manga_reader_and_requires_pipeline_trace",
        "assertions": 5,
        "imageReaderRootIds": list(image_root_ids),
        "requiredTraceEvent": "pipeline_result",
    }


def wait_for_sanitized_trace_records(
    driver: Any, by: Any, source_id: Optional[str], package: str, timeout: float
) -> list[Dict[str, Any]]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if current_bundle_name(driver) != package:
            return []
        records = get_sanitized_trace_records(driver, by, source_id)
        if records:
            return records
        driver.wait(0.4)
    return []


def wait_for_sanitized_workflow_trace_records(
    driver: Any,
    by: Any,
    source_id: Optional[str],
    package: str,
    timeout: float,
    required_workflow: str,
) -> list[Dict[str, Any]]:
    deadline = time.monotonic() + timeout
    latest_records: list[Dict[str, Any]] = []
    while time.monotonic() < deadline:
        if current_bundle_name(driver) != package:
            return latest_records
        records = get_sanitized_trace_records(driver, by, source_id)
        if records:
            latest_records = records
        for record in records:
            if record["workflow"] == required_workflow:
                return records
        driver.wait(0.4)
    return latest_records


def wait_for_readable_content_trace_records(
    driver: Any, by: Any, package: str, timeout: float, previous_content_trace_at: int
) -> list[Dict[str, Any]]:
    """Require a Content trace persisted after the reader action."""
    deadline = time.monotonic() + timeout
    latest_records: list[Dict[str, Any]] = []
    while time.monotonic() < deadline:
        if current_bundle_name(driver) != package:
            return []
        records = get_sanitized_trace_records(driver, by, None)
        apply_structured_content_diagnostics(driver, by, records)
        latest_records = records
        for record in records:
            if (
                record.get("workflow") == "content"
                and record.get("outputKind") == "content_readable"
                and int(record.get("contentCharacterCount", 0)) > 0
                and bool(record.get("contentFingerprint"))
                and int(record.get("traceOccurredAt", 0)) > previous_content_trace_at
            ):
                return records
        driver.wait(0.4)
    return latest_records


def has_fresh_readable_content_trace(
    records: list[Dict[str, Any]], previous_content_trace_at: int
) -> bool:
    """Whether the detail disclosure contains a post-reader Content witness."""
    for record in records:
        if (
            record.get("workflow") == "content"
            and record.get("outputKind") == "content_readable"
            and int(record.get("contentCharacterCount", 0)) > 0
            and bool(record.get("contentFingerprint"))
            and int(record.get("traceOccurredAt", 0)) > previous_content_trace_at
        ):
            return True
    return False


def wait_for_reader_content(driver: Any, by: Any, package: str, timeout: float) -> Dict[str, Any]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if current_bundle_name(driver) != package:
            raise RuntimeError("APP_EXITED_BEFORE_READER_CONTENT")
        root = driver.find_component(by.id(READER_ROOT_ID))
        if root is None:
            driver.wait(0.4)
            continue
        texts = get_text_components(driver, by)
        for component in texts[:120]:
            try:
                if component.getId() == READER_V2_CONTENT_REFRESH_DIAGNOSTIC_ID or component.getId() == READER_V2_CONTENT_EXECUTION_DIAGNOSTIC_ID:
                    continue
                value = component.getText()
            except Exception:
                continue
            if not isinstance(value, str):
                continue
            normalized = value.strip()
            if len(normalized) < 20 or normalized in ("加载中...", "开始阅读", "继续阅读"):
                continue
            if re.search(r"加载失败|Load failed|V2_EXECUTION_FAILED|V2 未就绪", normalized, re.IGNORECASE):
                raise RuntimeError("READER_CONTENT_LOAD_FAILURE")
            if re.search(r"</?(?:article|br|div|p|section|span)\b|&(nbsp|amp|lt|gt|quot|apos);", normalized):
                raise RuntimeError("READER_CONTENT_NOT_NORMALIZED")
            return {"visible_text_length": len(normalized)}
        driver.wait(0.5)
    raise RuntimeError("READER_CONTENT_TIMEOUT")


def wait_for_reader_v2_content_refresh_diagnostic(
    driver: Any, by: Any, package: str, timeout: float
) -> str:
    """Read the fixed, redacted initial Content-origin decision from the reader."""
    deadline = time.monotonic() + timeout
    pattern = re.compile(r"force=[01];origin=(?:network|persistent_cache|preparsed_cache|cache_candidate)")
    while time.monotonic() < deadline:
        if current_bundle_name(driver) != package:
            raise RuntimeError("APP_EXITED_BEFORE_READER_CONTENT_DECISION")
        component = driver.find_component(by.id(READER_V2_CONTENT_REFRESH_DIAGNOSTIC_ID))
        if component is not None:
            value = component.getText()
            if isinstance(value, str) and pattern.fullmatch(value):
                return value
        driver.wait(0.4)
    raise RuntimeError("READER_CONTENT_ORIGIN_DIAGNOSTIC_TIMEOUT")


def wait_for_reader_v2_content_execution_diagnostic(
    driver: Any,
    by: Any,
    package: str,
    timeout: float,
    previous_content_trace_at: int,
) -> str:
    """Require a fresh, persisted V2 Content result from this reader action."""
    deadline = time.monotonic() + timeout
    latest = ""
    while time.monotonic() < deadline:
        if current_bundle_name(driver) != package:
            raise RuntimeError("APP_EXITED_BEFORE_READER_CONTENT_EXECUTION")
        component = driver.find_component(by.id(READER_V2_CONTENT_EXECUTION_DIAGNOSTIC_ID))
        if component is not None:
            value = component.getText()
            if isinstance(value, str) and READER_V2_CONTENT_EXECUTION_PATTERN.fullmatch(value):
                latest = value
                parsed = reader_v2_content_execution_record(value)
                if (
                    value.startswith("state=ready;engine=v2;")
                    and ";digest=empty;" not in value
                    and ";digest=digest_error;" not in value
                    and ";traceAt=0;" not in value
                    and value.endswith("persisted=1")
                    and int(parsed["traceOccurredAt"]) > previous_content_trace_at
                ):
                    return value
                if value.startswith("state=empty;") or value.startswith("state=failed;"):
                    raise RuntimeError("READER_V2_CONTENT_RESULT_NOT_READABLE")
        driver.wait(0.4)
    if latest.startswith("state=ready;engine=legacy_or_blocked;"):
        raise RuntimeError("READER_V2_CONTENT_ENGINE_NOT_SELECTED")
    if latest.startswith("state=ready;engine=v2;") and ";traceAt=0;" in latest:
        raise RuntimeError("READER_V2_CONTENT_TRACE_NOT_RECORDED")
    if latest.startswith("state=ready;engine=v2;") and latest.endswith("persisted=0"):
        raise RuntimeError("READER_V2_CONTENT_TRACE_NOT_PERSISTED")
    if latest.startswith("state=ready;engine=v2;"):
        parsed = reader_v2_content_execution_record(latest)
        if int(parsed["traceOccurredAt"]) <= previous_content_trace_at:
            raise RuntimeError("READER_V2_CONTENT_TRACE_NOT_FRESH")
    raise RuntimeError("READER_V2_CONTENT_EXECUTION_DIAGNOSTIC_TIMEOUT")


def reader_v2_content_execution_record(value: str) -> Dict[str, Any]:
    """Convert the fixed, redacted reader diagnostic into typed evidence."""
    match = READER_V2_CONTENT_EXECUTION_PATTERN.fullmatch(value)
    if match is None:
        raise RuntimeError("READER_V2_CONTENT_EXECUTION_DIAGNOSTIC_INVALID")
    return {
        "state": match.group(1),
        "engine": match.group(2),
        "contentCharacterCount": int(match.group(3)),
        "contentFingerprint": match.group(4).lower(),
        "contentLineFeedCount": int(match.group(5)),
        "contentCarriageReturnCount": int(match.group(6)),
        "contentLeadingWhitespaceCount": int(match.group(7)),
        "contentTrailingWhitespaceCount": int(match.group(8)),
        "traceOccurredAt": int(match.group(9)),
        "tracePersisted": match.group(10) == "1",
    }


def parse_explore_trace_text(value: str) -> Dict[str, Any]:
    """Parse the fixed redacted Explore trace shown for success or failure."""
    match = EXPLORE_TRACE_PATTERN.fullmatch(value.strip())
    if match is None:
        raise RuntimeError("EXPLORE_TRACE_INVALID")
    return {
        "workflow": "explore",
        "transport": match.group(1),
        "statusCode": int(match.group(2)),
        "errorCode": match.group(3),
        "optionCount": int(match.group(4)),
        "variableCount": int(match.group(5)),
        "outputSummary": match.group(6),
    }


def wait_for_explore_kind_or_error(
    driver: Any, by: Any, timeout: float
) -> tuple[Optional[Any], Optional[Any]]:
    """Observe a usable kind and terminal error state in one bounded poll.

    A source can legitimately resolve to no executable category (for example,
    a decorative title with an empty URL). Waiting for the kind control alone
    hides that terminal state for the full UI timeout and prevents the runner
    from closing the Driver cleanly.
    """
    deadline = time.monotonic() + max(0.5, timeout)
    while time.monotonic() < deadline:
        kind = driver.find_component(by.id(explore_kind_id(0)))
        if kind is not None:
            return kind, None
        error_state = driver.find_component(by.id(BOOK_SOURCE_EXPLORE_ERROR_ID))
        if error_state is not None:
            return None, error_state
        driver.wait(0.4)
    return None, None


def execute_explore_workflow(
    driver: Any,
    by: Any,
    source_id: str,
    source_name: str,
    timeout: float,
    evidence: Dict[str, Any],
    continue_read_path: bool = False,
    image_workflow: bool = False,
    package: str = PACKAGE_NAME,
    hdc_path: Optional[str] = None,
) -> None:
    """Run the actual main-menu discovery path for one exact source.

    This intentionally uses the same picker, category and result controls as a
    user.  A non-empty card is not enough: the page must also expose the
    source-bound redacted Explore trace written by the V2 transport.
    """
    picker = wait_for_clickable(
        driver, by.id(BOOK_SOURCE_PICKER_OPEN_ID), "BOOK_SOURCE_PICKER_OPEN", timeout
    )
    picker.click()
    evidence["actions"].append("open_book_source_picker")
    picker_filter = driver.wait_for_component(
        by.id(BOOK_SOURCE_PICKER_FILTER_ID), timeout=timeout
    )
    if picker_filter is None:
        raise RuntimeError("BOOK_SOURCE_PICKER_FILTER_MISSING")
    if not picker_filter.isEnabled():
        raise RuntimeError("BOOK_SOURCE_PICKER_FILTER_DISABLED")
    driver.clear_text(picker_filter)
    driver.input_text(picker_filter, source_name)
    source_item = wait_for_clickable_with_bounded_scroll(
        driver,
        by.id(source_picker_item_id(source_id)),
        "BOOK_SOURCE_PICKER_ITEM",
        timeout,
        evidence,
        scroll_target=by.type("Scroll"),
    )
    source_item.click()
    evidence["actions"].append("select_exact_book_source_for_explore")
    kind, terminal_error = wait_for_explore_kind_or_error(driver, by, timeout)
    if kind is None:
        if terminal_error is not None:
            # No request is issued when the selected source has no executable
            # category. This is a terminal rule outcome, not a Driver timeout.
            evidence["explore_error"] = component_record(terminal_error)
            evidence["actions"].append("observe_explore_terminal_error")
            evidence["explore_outcome"] = "no_executable_kind"
            merge_workflow_results(evidence, {
                "search": "policy_blocked:search_workflow_missing",
                "book_info": "policy_blocked:explore_read_path_not_requested",
                "toc": "policy_blocked:explore_read_path_not_requested",
                "content": "policy_blocked:explore_read_path_not_requested",
                "explore": "failed:no_executable_kind",
                "file": "policy_blocked:explore_probe_file_workflow_not_declared",
                "review": "policy_blocked:explore_probe_review_workflow_not_declared",
            })
            raise RuntimeError("EXPLORE_NO_EXECUTABLE_KIND")
        raise RuntimeError("EXPLORE_KIND_MISSING")
    evidence["explore_kind"] = component_record(kind)
    evidence["actions"].append("observe_explore_kind")

    deadline = time.monotonic() + timeout
    result = None
    trace = None
    error_state = None
    empty_state = None
    while time.monotonic() < deadline:
        if current_bundle_name(driver) != PACKAGE_NAME:
            raise RuntimeError("APP_EXITED_DURING_EXPLORE")
        result = driver.find_component(by.id(explore_result_id(0)))
        trace = driver.find_component(by.id(BOOK_SOURCE_EXPLORE_TRACE_ID))
        error_state = driver.find_component(by.id(BOOK_SOURCE_EXPLORE_ERROR_ID))
        empty_state = driver.find_component(by.id(BOOK_SOURCE_EXPLORE_EMPTY_ID))
        if result is not None or error_state is not None or empty_state is not None:
            break
        driver.wait(0.4)
    if result is None:
        if error_state is not None:
            raise RuntimeError("EXPLORE_RESULT_ERROR_STATE")
        if empty_state is not None:
            evidence["explore_empty_state"] = component_record(empty_state)
            trace = driver.wait_for_component(
                by.id(BOOK_SOURCE_EXPLORE_TRACE_ID), timeout=timeout
            )
            if trace is None:
                raise RuntimeError("EXPLORE_TRACE_MISSING_ON_EMPTY")
            evidence["explore_trace"] = parse_explore_trace_text(str(trace.getText()))
            evidence["actions"].append("observe_explore_trace_on_empty")
            evidence["explore_outcome"] = "empty"
            merge_workflow_results(evidence, {
                "search": "policy_blocked:search_workflow_missing",
                "book_info": "policy_blocked:explore_read_path_not_requested",
                "toc": "policy_blocked:explore_read_path_not_requested",
                "content": "policy_blocked:explore_read_path_not_requested",
                "explore": "blocked:explore_empty_without_reference",
                "file": "policy_blocked:explore_probe_file_workflow_not_declared",
                "review": "policy_blocked:explore_probe_review_workflow_not_declared",
            })
            raise RuntimeError("EXPLORE_EMPTY_RESULT")
        raise RuntimeError("EXPLORE_RESULT_TIMEOUT")
    evidence["explore_result"] = component_record(result)
    evidence["actions"].append("observe_nonempty_explore_result")
    if trace is None:
        trace = driver.wait_for_component(by.id(BOOK_SOURCE_EXPLORE_TRACE_ID), timeout=timeout)
    if trace is None:
        # The Explore disclosure is rendered after the result cards inside the
        # same Scroll.  Hypium's ordinary component lookup only sees the
        # current viewport, so a valid V2 trace can be below the first card
        # even though the request and result have already completed.
        try:
            trace = driver.find_component(
                by.id(BOOK_SOURCE_EXPLORE_TRACE_ID),
                scroll_target=by.type("Scroll"),
            )
        except Exception as error:
            # Hypium 6.1.0.210 can reject scrollSearch with offset=401 on a
            # large ArkUI Scroll.  Keep that transport/tool error in memory
            # only and use bounded small swipes instead of failing the source.
            trace = None
            evidence["explore_trace_scroll_search_error"] = type(error).__name__
        if trace is not None:
            evidence["actions"].append("scroll_to_explore_trace")
    if trace is None:
        from hypium.model.basic_data_type import UiParam

        for _ in range(12):
            trace = driver.find_component(by.id(BOOK_SOURCE_EXPLORE_TRACE_ID))
            if trace is not None:
                evidence["actions"].append("observe_explore_trace_after_small_swipe")
                break
            try:
                driver.swipe(UiParam.UP, distance=60, area=by.type("Scroll"))
            except Exception as error:
                evidence["explore_trace_swipe_error"] = type(error).__name__
                break
            driver.wait(0.3)
    if trace is None:
        raise RuntimeError("EXPLORE_TRACE_MISSING")
    evidence["explore_trace"] = parse_explore_trace_text(str(trace.getText()))
    evidence["actions"].append("observe_explore_trace")
    trace_ok = (
        evidence["explore_trace"]["statusCode"] >= 200
        and evidence["explore_trace"]["statusCode"] < 400
        and evidence["explore_trace"]["errorCode"] == "none"
        and evidence["explore_trace"]["outputSummary"] != "empty"
    )
    evidence["explore_outcome"] = "result" if trace_ok else "trace_unreadable"
    merge_workflow_results(evidence, {
        "search": "policy_blocked:search_workflow_missing",
        "book_info": (
            "running:explore_read_path_requested"
            if continue_read_path
            else "policy_blocked:explore_read_path_not_requested"
        ),
        "toc": (
            "running:explore_read_path_requested"
            if continue_read_path
            else "policy_blocked:explore_read_path_not_requested"
        ),
        "content": (
            "running:explore_read_path_requested"
            if continue_read_path
            else "policy_blocked:explore_read_path_not_requested"
        ),
        "explore": "passed:explore_execution_verified" if trace_ok else "failed:explore_trace_unreadable",
        "file": "policy_blocked:explore_probe_file_workflow_not_declared",
        "review": "policy_blocked:explore_probe_review_workflow_not_declared",
    })
    if not trace_ok:
        raise RuntimeError("EXPLORE_TRACE_UNREADABLE")
    if continue_read_path:
        # The trace disclosure can be below the first result card. Re-resolve
        # the semantic result after bounded downward swipes rather than
        # clicking a stale Hypium component handle or guessing coordinates.
        from hypium.model.basic_data_type import UiParam

        selected_result = driver.find_component(by.id(explore_result_id(0)))
        for _ in range(12):
            if selected_result is not None:
                break
            try:
                driver.swipe(UiParam.DOWN, distance=80, area=by.type("Scroll"))
            except Exception as error:
                evidence["explore_result_restore_error"] = type(error).__name__
                break
            driver.wait(0.3)
            selected_result = driver.find_component(by.id(explore_result_id(0)))
        if selected_result is None:
            selected_result = result
        if selected_result is None or not selected_result.isEnabled() or not selected_result.isClickable():
            raise RuntimeError("EXPLORE_RESULT_NOT_REVISIBLE")
        evidence["explore_read_path"] = "requested"
        evidence["actions"].append("continue_explore_result_to_read_path")
        execute_safe_read_path(
            driver,
            by,
            source_id,
            package,
            timeout,
            evidence,
            image_workflow=image_workflow,
            hdc_path=hdc_path,
            result_component=selected_result,
            entry_workflow="explore",
        )
        evidence["explore_read_path"] = "executed"
        merge_workflow_results(
            evidence,
            {
                "explore": "passed:explore_execution_verified",
                "explore_read_path": "passed:book_info_toc_content_attempted",
            },
        )


def merge_workflow_results(
    evidence: Dict[str, Any], updates: Dict[str, str]
) -> None:
    """Merge workflow results without discarding an earlier Explore witness."""
    existing = evidence.get("workflow_results")
    merged: Dict[str, str] = {}
    if isinstance(existing, dict):
        for key, value in existing.items():
            merged[str(key)] = str(value)
    for key, value in updates.items():
        merged[str(key)] = str(value)
    evidence["workflow_results"] = merged


def execute_safe_read_path(
    driver: Any,
    by: Any,
    source_id: str,
    package: str,
    timeout: float,
    evidence: Dict[str, Any],
    image_workflow: bool = False,
    hdc_path: Optional[str] = None,
    result_component: Optional[Any] = None,
    entry_workflow: str = "search",
) -> None:
    token = source_automation_token(source_id)
    from_explore_result = result_component is not None
    if result_component is None:
        result = wait_for_clickable(
            driver, by.id(f"novel_search_result_{token}_0"), "SEARCH_FIRST_RESULT", timeout
        )
    else:
        result = result_component
        if not result.isEnabled() or not result.isClickable():
            result = wait_for_clickable(
                driver,
                by.id(explore_result_id(0)),
                "EXPLORE_FIRST_RESULT",
                timeout,
            )
    # Search-result test ids can encode a book target. Retain geometry and
    # interaction state only; the immutable source hash already binds this run.
    evidence["first_search_result"] = component_record(result, redact_source_identity=True)
    result.click()
    evidence["actions"].append("open_explore_result" if from_explore_result else "open_book_detail")
    detail_root = wait_for_first_component_by_id(
        driver, by, (DETAIL_ROOT_ID, UNIFIED_DETAIL_ROOT_ID), "DETAIL_ROOT", timeout
    )
    # A fresh install can show the five-step unified-detail guide above the
    # actual controls.  It is a real modal overlay: Hypium can still resolve
    # the underlying reading button, but the click is intercepted and no
    # product callback runs.  Dismiss only the guide's stable semantic target
    # and record it as a prerequisite, never as a reader result.
    guide_skip = driver.find_component(by.id(APP_GUIDE_SKIP_BUTTON_ID))
    if guide_skip is not None:
        if not guide_skip.isEnabled() or not guide_skip.isClickable():
            raise RuntimeError("APP_GUIDE_SKIP_NOT_INTERACTABLE")
        guide_skip.click()
        evidence["actions"].append("dismiss_unified_detail_guide")
        driver.wait_for_idle(idle_time=0.2, timeout=10)
        if driver.find_component(by.id(APP_GUIDE_SKIP_BUTTON_ID)) is not None:
            raise RuntimeError("APP_GUIDE_DISMISS_NOT_CONFIRMED")
    chapter_count = wait_for_first_component_by_id(
        driver,
        by,
        (
            DETAIL_CHAPTER_COUNT_ID,
            UNIFIED_DETAIL_CHAPTER_COUNT_PORTRAIT_ID,
            UNIFIED_DETAIL_CHAPTER_COUNT_LANDSCAPE_ID,
        ),
        "DETAIL_CHAPTER_COUNT",
        timeout,
    )
    chapter_match = re.fullmatch(r"([1-9]\d*)章", str(chapter_count.getText()).strip())
    evidence["detail"] = {
        "root": component_record(detail_root),
        "chapter_count_kind": "positive" if chapter_match is not None else "empty_or_non_positive",
    }
    # The inline evidence has the same redacted grammar as the visible
    # disclosure, but remains active when a long chapter list virtualizes the
    # expanded disclosure. Wait for TOC before touching the UI toggle: a
    # completed BookInfo can legitimately precede a multi-page TOC.
    inline_detail_trace_records = wait_for_sanitized_workflow_trace_records(
        driver, by, None, package, timeout, "toc"
    )
    if inline_detail_trace_records:
        evidence["detail_trace_records"] = inline_detail_trace_records
        evidence["detail_trace_transport"] = "inline_stable_evidence"
    detail_trace_toggle = driver.find_component(by.id(UNIFIED_DETAIL_TRACE_TOGGLE_ID))
    if detail_trace_toggle is None and image_workflow:
        # IMAGE detail is supplied by an async bridge. A one-shot find races
        # its BookInfo/TOC commit and had been masking available V2 evidence
        # as a Harness defect. Wait briefly but keep asset evidence separate
        # when the bridge truly emits no detail disclosure.
        optional_deadline = time.monotonic() + min(timeout, 15.0)
        while time.monotonic() < optional_deadline:
            detail_trace_toggle = driver.find_component(by.id(UNIFIED_DETAIL_TRACE_TOGGLE_ID))
            if detail_trace_toggle is not None:
                break
            driver.wait(0.4)
        if detail_trace_toggle is None:
            evidence["detail_trace_toggle"] = "missing_after_image_wait"
            evidence["detail_trace_records"] = wait_for_sanitized_trace_records(
                driver, by, None, package, min(timeout, 10.0)
            )
    if detail_trace_toggle is not None and not inline_detail_trace_records:
        detail_trace_toggle = wait_for_clickable(
            driver,
            by.id(UNIFIED_DETAIL_TRACE_TOGGLE_ID),
            "DETAIL_TRACE_TOGGLE",
            timeout,
        )
        detail_trace_toggle.click()
        evidence["actions"].append("expand_detail_trace")
        detail_trace_detail = None
        for attempt_index in range(DETAIL_TRACE_REHYDRATION_MAX_ATTEMPTS):
            detail_trace_detail = driver.wait_for_component(
                by.id(UNIFIED_DETAIL_TRACE_DETAIL_ID), timeout=min(timeout, 15.0)
            )
            if detail_trace_detail is not None:
                break
            refreshed_toggle = driver.wait_for_component(
                by.id(UNIFIED_DETAIL_TRACE_TOGGLE_ID), timeout=min(timeout, 15.0)
            )
            if refreshed_toggle is None:
                continue
            if str(refreshed_toggle.getText()).strip() == "执行诊断":
                refreshed_toggle = wait_for_clickable(
                    driver,
                    by.id(UNIFIED_DETAIL_TRACE_TOGGLE_ID),
                    "DETAIL_TRACE_REHYDRATION_TOGGLE",
                    timeout,
                )
                refreshed_toggle.click()
                evidence["actions"].append("retry_expand_detail_trace_after_rehydration")
            else:
                driver.wait(0.8)
        evidence["detail_trace_rehydration_attempts"] = DETAIL_TRACE_REHYDRATION_MAX_ATTEMPTS
        if detail_trace_detail is None:
            raise RuntimeError("DETAIL_TRACE_DETAIL_MISSING")
    # Never persist visible diagnostic text. The parser keeps only fixed trace
    # fields and output hashes. Book-info may terminate before a TOC request
    # is planned, which is a distinct workflow result rather than a missing
    # device trace.
    if not inline_detail_trace_records and detail_trace_toggle is not None:
        evidence["detail_trace_records"] = wait_for_sanitized_trace_records(
            driver, by, None, package, timeout
        )
    evidence["detail_trace_storage_diagnostic"] = read_storage_diagnostic(driver, by)
    # Detail loading awaits BookInfo and then TOC. The first trace can therefore
    # be a valid BookInfo record while the TOC request is still in flight.
    # Preserve the latest trace set on timeout so a genuine terminal BookInfo
    # result remains distinguishable from a runner short-circuit.
    if any(record["workflow"] == "book_info" for record in evidence["detail_trace_records"]) and not any(
        record["workflow"] == "toc" for record in evidence["detail_trace_records"]
    ):
        evidence["detail_trace_records"] = wait_for_sanitized_workflow_trace_records(
            driver, by, None, package, timeout, "toc"
        )
    apply_structured_content_diagnostics(driver, by, evidence["detail_trace_records"])
    if not evidence["detail_trace_records"] and not image_workflow:
        raise RuntimeError("DETAIL_TRACE_RECORDS_MISSING")
    has_book_info_trace = any(
        record["workflow"] == "book_info"
        for record in evidence["detail_trace_records"]
    )
    has_toc_trace = any(
        record["workflow"] == "toc"
        for record in evidence["detail_trace_records"]
    )
    if not has_book_info_trace and not image_workflow:
        raise RuntimeError("DETAIL_BOOK_INFO_TRACE_MISSING")
    book_info_result = "passed"
    for record in evidence["detail_trace_records"]:
        if record["workflow"] == "book_info" and record["errorCode"] in ("http", "network") and record.get("bookInfoResolvedCount", 0) == 0:
            book_info_result = "metadata_empty_http_error"
            break
    if not has_toc_trace and not image_workflow:
        merge_workflow_results(evidence, {
            entry_workflow: "passed",
            "book_info": book_info_result if book_info_result != "passed" else "terminal_trace_observed",
            "toc": "not_started_book_info_terminal",
            "content": "not_executed_book_info_terminal",
        })
        return
    previous_content_trace_at = 0
    for record in evidence["detail_trace_records"]:
        if record.get("workflow") == "content":
            previous_content_trace_at = max(
                previous_content_trace_at, int(record.get("traceOccurredAt", 0))
            )
    evidence["previous_content_trace_at"] = previous_content_trace_at
    toc_trace_nonempty = any(
        record["workflow"] == "toc"
        and record["errorCode"] == "none"
        and record["outputKind"] == "toc_nonempty"
        and int(record.get("chapterCount", 0)) > 0
        for record in evidence["detail_trace_records"]
    )
    if chapter_match is None and not image_workflow:
        if not toc_trace_nonempty:
            merge_workflow_results(evidence, {
                entry_workflow: "passed",
                "book_info": book_info_result,
                "toc": "empty_or_unconfirmed",
                "content": "not_executed_no_toc",
            })
            return
        # The trace is an engine-owned result while the count label is a
        # presentation snapshot. Do not turn a completed nonempty TOC into an
        # engine failure just because this label has not rendered yet.
        evidence["detail"]["chapter_count_kind"] = "trace_nonempty_ui_count_unavailable"
    elif chapter_match is None and image_workflow and toc_trace_nonempty:
        # IMAGE uses a staged manga-detail adapter. The static count can still
        # be the initial zero snapshot when the V2 TOC trace first arrives.
        # Wait for the real projection before calling it a UI contract break.
        rendered_chapter_count = wait_for_positive_detail_chapter_count(
            driver, by, min(timeout, 20.0)
        )
        if rendered_chapter_count is None:
            evidence["detail"]["chapter_count_kind"] = "trace_nonempty_ui_count_unavailable"
        else:
            evidence["detail"]["chapter_count"] = rendered_chapter_count
            evidence["detail"]["chapter_count_kind"] = "positive_after_toc_trace"
    elif chapter_match is not None:
        evidence["detail"]["chapter_count"] = int(chapter_match.group(1))
    # The expanded diagnostic disclosure can push the detail action row out of
    # ArkUI's active component tree. Collapse it before resolving the real
    # reader action so a virtualized, off-screen button is not misclassified
    # as a missing product control.
    if detail_trace_toggle is not None:
        detail_trace_toggle = wait_for_clickable(
            driver,
            by.id(UNIFIED_DETAIL_TRACE_TOGGLE_ID),
            "DETAIL_TRACE_TOGGLE_COLLAPSE",
            timeout,
        )
        detail_trace_toggle.click()
        evidence["actions"].append("collapse_detail_trace")
        # Rehydration after dismissing a page guide can recreate the
        # disclosure one frame after the first click.  Re-resolve the toggle
        # and wait for the detail node to actually detach instead of treating
        # that transient frame as a product failure.
        collapsed = False
        collapse_deadline = time.monotonic() + min(timeout, 8.0)
        while time.monotonic() < collapse_deadline:
            driver.wait(0.4)
            if driver.find_component(by.id(UNIFIED_DETAIL_TRACE_DETAIL_ID)) is None:
                collapsed = True
                break
            refreshed_toggle = driver.find_component(by.id(UNIFIED_DETAIL_TRACE_TOGGLE_ID))
            if refreshed_toggle is not None and refreshed_toggle.isEnabled() and refreshed_toggle.isClickable():
                refreshed_text = str(refreshed_toggle.getText()).strip()
                if refreshed_text in ("收起诊断", "收起"):
                    refreshed_toggle.click()
                    evidence["actions"].append("retry_collapse_detail_trace")
        if not collapsed:
            raise RuntimeError("DETAIL_TRACE_DETAIL_NOT_COLLAPSED")
    image_trace_before_keys: set[str] = set()
    if image_workflow:
        # HILOG retains prior invocations. Establish the boundary before the
        # reader is opened so the returned trace cannot be satisfied by an old
        # test run for the same source.
        image_trace_before = capture_image_trace_snapshot(hdc_path, driver.device_sn)
        image_trace_before_keys = {image_trace_event_key(event) for event in image_trace_before}
        evidence["image_trace_before_event_count"] = len(image_trace_before)
    start_reading = wait_for_first_clickable_by_id(
        driver,
        by,
        (
            DETAIL_START_READING_ID,
            UNIFIED_DETAIL_START_READING_PORTRAIT_ID,
            UNIFIED_DETAIL_START_READING_LANDSCAPE_ID,
        ),
        "DETAIL_START_READING",
        timeout,
    )
    start_reading.click()
    evidence["actions"].append("open_novel_reader")
    # Isolated reader navigation is intentionally dispatched after the book
    # open transition completes. On real devices that transition can exceed
    # the old 10-second observation window even though the navigation is
    # healthy, so retain the normal source timeout while bounding this route
    # handoff separately.
    reader_root = wait_for_first_component_by_id(
        driver,
        by,
        reader_root_ids_for_workflow(image_workflow),
        "IMAGE_READER_ROOT" if image_workflow else "READER_ROOT",
        min(timeout, 30.0),
    )
    if image_workflow:
        image_trace: list[Dict[str, Any]] = []
        reader_trace_deadline = time.monotonic() + min(timeout, 8.0)
        while time.monotonic() < reader_trace_deadline:
            driver.wait(0.4)
            latest_image_trace = capture_image_trace_snapshot(hdc_path, driver.device_sn)
            fresh_events = [
                event for event in latest_image_trace
                if image_trace_event_key(event) not in image_trace_before_keys
            ]
            image_trace = fresh_events
            if has_required_image_pipeline_result(fresh_events):
                break
        image_trace_summary = summarize_image_trace(image_trace)
        image_trace_summary["freshness"] = "post_reader_delta"
        image_trace_summary["events"] = image_trace
        evidence["image_trace"] = image_trace_summary
        if not has_required_image_pipeline_result(image_trace):
            merge_workflow_results(evidence, {
                entry_workflow: "passed",
                "book_info": "trace_observed" if has_book_info_trace else "unverified",
                "toc": "trace_observed" if has_toc_trace else "unverified",
                "content": "failed:image_pipeline_trace_missing",
            })
            raise RuntimeError("IMAGE_PIPELINE_TRACE_MISSING")
        merge_workflow_results(evidence, {
            entry_workflow: "passed",
            "book_info": "trace_observed" if has_book_info_trace else "unverified",
            "toc": "trace_observed" if has_toc_trace else "unverified",
            "content": "image_reader_trace_captured",
        })
        evidence["reader"] = {"root": component_record(reader_root)}
        return
    reader_execution = wait_for_reader_v2_content_execution_diagnostic(
        driver, by, package, timeout, previous_content_trace_at
    )
    reader_execution_evidence = reader_v2_content_execution_record(reader_execution)
    evidence["reader"] = {
        "root": component_record(reader_root),
        "content": wait_for_reader_content(driver, by, package, timeout),
        "v2_content_refresh": wait_for_reader_v2_content_refresh_diagnostic(
            driver, by, package, timeout
        ),
        "v2_content_execution": reader_execution,
        "v2_content_execution_evidence": reader_execution_evidence,
    }
    evidence["reader_content_trace_at"] = int(
        reader_execution_evidence["traceOccurredAt"]
    )
    if evidence["reader"]["v2_content_refresh"] != "force=1;origin=network":
        raise RuntimeError("READER_FORCED_CONTENT_NETWORK_BYPASS_NOT_OBSERVED")
    driver.go_back()
    evidence["actions"].append("return_to_detail_after_reader")
    detail_root = wait_for_first_component_by_id(
        driver, by, (DETAIL_ROOT_ID, UNIFIED_DETAIL_ROOT_ID), "DETAIL_ROOT_AFTER_READER", timeout
    )
    if detail_root is None:
        raise RuntimeError("DETAIL_ROOT_AFTER_READER_MISSING")
    detail_trace_toggle = wait_for_clickable(
        driver, by.id(UNIFIED_DETAIL_TRACE_TOGGLE_ID), "DETAIL_TRACE_TOGGLE_AFTER_READER", timeout
    )
    detail_trace_toggle.click()
    evidence["actions"].append("expand_detail_trace_after_reader")
    detail_trace_detail = driver.wait_for_component(
        by.id(UNIFIED_DETAIL_TRACE_DETAIL_ID), timeout=timeout
    )
    if detail_trace_detail is None:
        raise RuntimeError("DETAIL_TRACE_DETAIL_AFTER_READER_MISSING")
    # Give the normal return-path rehydration a short opportunity first. If it
    # still exposes only the pre-reader snapshot, exercise the disclosure's
    # explicit refresh boundary once. This is a stable, reversible UI action
    # and prevents a return-animation snapshot from being mistaken for a
    # durable cross-Ability visibility failure.
    first_wait_timeout = min(timeout, 5.0)
    post_reader_records = wait_for_readable_content_trace_records(
        driver, by, package, first_wait_timeout, previous_content_trace_at
    )
    if not has_fresh_readable_content_trace(
        post_reader_records, previous_content_trace_at
    ):
        # This is a reversible diagnostic refresh, not a content-loading
        # workflow. Bound it separately so a stale detail projection yields a
        # classified evidence result and reaches finally/driver.close() rather
        # than consuming the entire safe-read process budget.
        refresh_timeout = min(timeout, 20.0)
        detail_trace_toggle = wait_for_clickable(
            driver,
            by.id(UNIFIED_DETAIL_TRACE_TOGGLE_ID),
            "DETAIL_TRACE_TOGGLE_REFRESH_COLLAPSE",
            refresh_timeout,
        )
        detail_trace_toggle.click()
        evidence["actions"].append("collapse_detail_trace_refresh")
        driver.wait_for_idle(idle_time=0.2, timeout=10)
        detail_trace_toggle = wait_for_clickable(
            driver,
            by.id(UNIFIED_DETAIL_TRACE_TOGGLE_ID),
            "DETAIL_TRACE_TOGGLE_REFRESH_EXPAND",
            refresh_timeout,
        )
        detail_trace_toggle.click()
        evidence["actions"].append("expand_detail_trace_refresh")
        detail_trace_detail = driver.wait_for_component(
            by.id(UNIFIED_DETAIL_TRACE_DETAIL_ID), timeout=refresh_timeout
        )
        if detail_trace_detail is None:
            raise RuntimeError("DETAIL_TRACE_DETAIL_AFTER_REFRESH_MISSING")
        post_reader_records = wait_for_readable_content_trace_records(
            driver, by, package, refresh_timeout, previous_content_trace_at
        )
    evidence["post_reader_trace_storage_diagnostic"] = read_storage_diagnostic(driver, by)
    content_records = [
        record for record in post_reader_records if record["workflow"] == "content"
    ]
    if not content_records:
        raise RuntimeError("CONTENT_TRACE_AFTER_READER_MISSING")
    # Detail diagnostics preserve their storage order, which is not a temporal
    # ordering contract. Select the newest Content trace explicitly so an
    # older persisted record cannot overwrite the fresh-reader witness.
    content_record = max(
        content_records, key=lambda record: int(record.get("traceOccurredAt", 0))
    )
    if (
        content_record.get("outputKind") != "content_readable"
        or int(content_record.get("contentCharacterCount", 0)) <= 0
        or not content_record.get("contentFingerprint")
    ):
        raise RuntimeError("CONTENT_TRACE_AFTER_READER_NOT_READABLE")
    post_reader_content_trace_at = int(content_record.get("traceOccurredAt", 0))
    if post_reader_content_trace_at <= previous_content_trace_at:
        raise RuntimeError("CONTENT_TRACE_TIMESTAMP_NOT_ADVANCED")
    # The reader probe reports the summary update time, while the detail
    # projection deliberately exposes the trace occurrence time. The same
    # persistence transaction therefore normally has a small positive delta
    # (occurredAt <= updatedAt); require bounded temporal proximity instead of
    # imposing an invalid timestamp ordering between different fields.
    reader_trace_updated_at = int(reader_execution_evidence["traceOccurredAt"])
    if abs(post_reader_content_trace_at - reader_trace_updated_at) > 5000:
        raise RuntimeError("CONTENT_TRACE_NOT_ASSOCIATED_WITH_READER_ACTION")
    # Persist both endpoints of the monotonic evidence gate. These values are
    # timestamps only; the runner keeps no page text, URL, header, or cookie.
    evidence["previous_content_trace_at"] = previous_content_trace_at
    evidence["content_trace_after_reader_at"] = post_reader_content_trace_at
    evidence["detail_trace_records"] = post_reader_records
    merge_workflow_results(evidence, {
        entry_workflow: "passed",
        "book_info": book_info_result,
        "toc": "passed",
        "content": "passed",
    })


def write_json_atomically(path: Path, value: Dict[str, Any]) -> None:
    temporary_path = path.with_suffix(path.suffix + ".tmp")
    temporary_path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    temporary_path.replace(path)


def write_checkpoint(output_dir: Path, evidence: Dict[str, Any], stage: str) -> None:
    evidence["checkpoint_stage"] = stage
    checkpoint = {
        "schema_version": 1,
        "stage": stage,
        "status": evidence["status"],
        "actions": evidence["actions"],
        "screenshots": evidence["screenshots"],
        "updated_at_epoch_ms": int(time.time() * 1000),
    }
    write_json_atomically(output_dir / "checkpoint.json", checkpoint)


def write_evidence(output_dir: Path, evidence: Dict[str, Any]) -> None:
    write_json_atomically(output_dir / "result.json", evidence)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device-sn")
    parser.add_argument("--hdc-path", help="Path to hdc.exe; HDC_PATH is also supported")
    parser.add_argument("--package", default=PACKAGE_NAME)
    parser.add_argument("--ability", default=ABILITY_NAME)
    parser.add_argument("--output-dir")
    parser.add_argument(
        "--parser-self-test",
        action="store_true",
        help="Verify the fixed, sanitized BookInfo trace parser without a device",
    )
    parser.add_argument(
        "--image-explore-contract-self-test",
        action="store_true",
        help="Verify IMAGE Explore routing invariants without a device",
    )
    # Network-backed source workflows may legitimately need longer than the
    # UI's short idle period. Keep this bounded while avoiding a false
    # ui_timeout immediately before an explicit V2 error state is rendered.
    parser.add_argument("--timeout", type=float, default=45.0)
    parser.add_argument("--source-id", help="Exact imported source ID for an optional card navigation check")
    parser.add_argument("--source-name", help="Exact source name used only to populate the local filter")
    parser.add_argument(
        "--filter-only",
        action="store_true",
        help="Verify exact source-name filtering without opening its workflow",
    )
    parser.add_argument(
        "--verify-filter-trace-detail",
        action="store_true",
        help="Open and close the full redacted V2 trace from the exact-filter card",
    )
    parser.add_argument(
        "--search-keyword",
        help="Run exactly one caller-authorized search after single-source navigation",
    )
    parser.add_argument(
        "--safe-read-path",
        action="store_true",
        help="Follow the idempotent result-detail-toc-content reader path after a successful search",
    )
    parser.add_argument(
        "--explore-workflow",
        action="store_true",
        help="Run the main-menu source-picker/category/discovery workflow for one exact source",
    )
    parser.add_argument(
        "--explore-read-path",
        action="store_true",
        help="After a non-empty Explore result, continue through BookInfo/Toc/Content using the guarded reader path",
    )
    parser.add_argument(
        "--image-workflow",
        action="store_true",
        help="Use the IMAGE detail and manga-reader path instead of the novel reader contract",
    )
    parser.add_argument(
        "--verify-v2-policy-details",
        action="store_true",
        help="Expand and collapse the V2 policy disclosure using stable component ids",
    )
    parser.add_argument(
        "--enable-v2-full-cutover",
        action="store_true",
        help="Set the global policy to V2 full cutover and verify its semantic summary",
    )
    parser.add_argument(
        "--safe-ui-audit",
        action="store_true",
        help="Capture only a management view filtered to an empty result, never source cards",
    )
    parser.add_argument(
        "--capture-visual-evidence",
        action="store_true",
        help="Opt in to screenshots for a separately authorized non-content visual audit",
    )
    parser.add_argument("--leave-app", action="store_true")
    args = parser.parse_args()
    if args.parser_self_test or args.image_explore_contract_self_test:
        return args
    if args.device_sn is None:
        parser.error("--device-sn is required unless --parser-self-test is used")
    if args.output_dir is None:
        parser.error("--output-dir is required unless --parser-self-test is used")
    if (args.source_id is None) != (args.source_name is None):
        parser.error("--source-id and --source-name must be provided together")
    if args.search_keyword is not None and args.source_id is None:
        parser.error("--search-keyword requires --source-id and --source-name")
    if args.safe_read_path and args.search_keyword is None:
        parser.error("--safe-read-path requires --search-keyword")
    if args.explore_workflow and args.safe_read_path:
        parser.error("--explore-workflow cannot be combined with --safe-read-path")
    if args.explore_read_path and not args.explore_workflow:
        parser.error("--explore-read-path requires --explore-workflow")
    if args.explore_read_path and args.safe_read_path:
        parser.error("--explore-read-path cannot be combined with --safe-read-path")
    if args.explore_workflow and args.search_keyword is not None:
        parser.error("--explore-workflow cannot be combined with --search-keyword")
    if args.explore_workflow and args.source_id is None:
        parser.error("--explore-workflow requires --source-id and --source-name")
    if args.safe_ui_audit and args.source_id is not None:
        parser.error("--safe-ui-audit cannot be combined with source-card navigation")
    if args.filter_only and args.search_keyword is not None:
        parser.error("--filter-only cannot be combined with --search-keyword")
    if args.verify_filter_trace_detail and not args.filter_only:
        parser.error("--verify-filter-trace-detail requires --filter-only")
    return args


def run(args: argparse.Namespace) -> int:
    output_dir = Path(args.output_dir).resolve()
    report_dir = output_dir / "hypium-report"
    output_dir.mkdir(parents=True, exist_ok=True)
    report_dir.mkdir(parents=True, exist_ok=True)
    evidence: Dict[str, Any] = {
        "status": "failed",
        "device_sn": args.device_sn,
        "package": args.package,
        "ability": args.ability,
        "output_dir": str(output_dir),
        "workflow": (
            "book_source_tab_explore_read_path"
            if args.explore_read_path
            else "book_source_tab_explore"
            if args.explore_workflow
            else "book_source_tab_to_v2_management"
        ),
        "actions": [],
        "screenshots": {},
        "driver_closed": False,
    }
    write_checkpoint(output_dir, evidence, "initialized")
    driver: Any = None
    exit_code = 1

    try:
        configure_hdc(args.hdc_path)
        from hypium.action.device.uidriver import UiDriver
        from hypium.model.basic_data_type import KeyCode
        from hypium.uidriver.by import BY

        install_hypium_forward_port_policy()
        evidence["hypium_forward_port_policy"] = "high_port_46000_46999"

        driver = UiDriver.connect(
            device_sn=args.device_sn,
            report_path=str(report_dir),
            log_level="info",
        )
        evidence["connected_device_sn"] = driver.device_sn
        evidence["display_size"] = driver.get_display_size()
        evidence["actions"].append("connect")
        write_checkpoint(output_dir, evidence, "driver_connected")

        driver.unlock()
        evidence["actions"].append("unlock")
        driver.stop_app(args.package)
        evidence["actions"].append("stop_app")
        # A replacement HAP can coexist briefly with the previous ArkTS
        # runtime. Settle the stop before starting the ability so each
        # evidence run executes the binary that was just installed.
        driver.wait(1.0)
        evidence["actions"].append("stop_app_settled")
        driver.start_app(args.package, args.ability, wait_time=1)
        driver.wait_for_idle(idle_time=0.2, timeout=10)
        driver.check_current_window(bundle_name=args.package)
        evidence["actions"].extend(["start_app", "check_current_window"])
        if args.capture_visual_evidence and not args.safe_ui_audit:
            evidence["screenshots"]["initial"] = driver.capture_screen(
                str(output_dir / "01-main-menu.jpeg")
            )
        write_checkpoint(output_dir, evidence, "main_menu_captured")

        initial_route = wait_for_initial_route(driver, BY, args.timeout)
        evidence["initial_route"] = initial_route
        if initial_route == "main_menu":
            book_source_tab = wait_for_clickable(
                driver, BY.id(BOOK_SOURCE_TAB_ID), "BOOK_SOURCE_TAB", args.timeout
            )
            evidence["book_source_tab"] = component_record(book_source_tab)
            book_source_tab.click()
            driver.wait_for_idle(idle_time=0.2, timeout=10)
            # MainMenu's Swiper uses a 260 ms page transition. wait_for_idle
            # only observes short UI quiescence and can capture an in-between
            # frame where the previous tab is translated across the viewport.
            driver.wait(0.8)
            evidence["actions"].append("click_book_source_tab")
            if args.capture_visual_evidence and not args.safe_ui_audit:
                evidence["screenshots"]["book_source_tab"] = driver.capture_screen(
                    str(output_dir / "02-book-source-tab.jpeg")
                )
            write_checkpoint(output_dir, evidence, "book_source_tab_captured")

            if args.explore_workflow:
                execute_explore_workflow(
                    driver,
                    BY,
                    args.source_id,
                    args.source_name,
                    args.timeout,
                    evidence,
                    continue_read_path=args.explore_read_path,
                    image_workflow=args.image_workflow,
                    package=args.package,
                    hdc_path=args.hdc_path,
                )
                evidence["status"] = "passed"
                evidence["actions"].append(
                    "complete_explore_read_path"
                    if args.explore_read_path
                    else "complete_explore_workflow"
                )
                write_checkpoint(output_dir, evidence, "explore_workflow_verified")
                exit_code = 0
                return exit_code

            manager_button = wait_for_clickable(
                driver, BY.id(BOOK_SOURCE_MANAGER_ID), "BOOK_SOURCE_MANAGER", args.timeout
            )
            evidence["book_source_manager"] = component_record(manager_button)
            manager_button.click()
            driver.wait_for_idle(idle_time=0.2, timeout=10)
            evidence["actions"].append("click_book_source_manager")
            write_checkpoint(output_dir, evidence, "source_management_opened")
        else:
            evidence["actions"].append("reuse_source_management_route")

            if args.explore_workflow:
                execute_explore_workflow(
                    driver,
                    BY,
                    args.source_id,
                    args.source_name,
                    args.timeout,
                    evidence,
                    continue_read_path=args.explore_read_path,
                    image_workflow=args.image_workflow,
                    package=args.package,
                    hdc_path=args.hdc_path,
                )
                evidence["status"] = "passed"
                evidence["actions"].append(
                    "complete_explore_read_path"
                    if args.explore_read_path
                    else "complete_explore_workflow"
                )
                write_checkpoint(output_dir, evidence, "explore_workflow_verified")
                exit_code = 0
                return exit_code

        v2_full_cutover = wait_for_clickable(
            driver, BY.id(V2_FULL_CUTOVER_ID), "V2_FULL_CUTOVER", args.timeout
        )
        evidence["v2_full_cutover"] = component_record(v2_full_cutover)
        evidence["actions"].append("verify_v2_full_cutover_control")

        if args.enable_v2_full_cutover:
            v2_full_cutover.click()
            driver.wait_for_idle(idle_time=0.2, timeout=10)
            policy_summary = driver.wait_for_component(
                BY.id(V2_POLICY_SUMMARY_ID), timeout=args.timeout
            )
            if policy_summary is None or "V2 全量切换" not in policy_summary.getText():
                raise RuntimeError("V2_FULL_CUTOVER_POLICY_NOT_APPLIED")
            evidence["v2_policy_summary"] = component_record(policy_summary)
            evidence["actions"].append("enable_v2_full_cutover")

        if args.verify_v2_policy_details:
            details_toggle = wait_for_clickable(
                driver, BY.id(V2_POLICY_DETAIL_TOGGLE_ID), "V2_POLICY_DETAIL_TOGGLE", args.timeout
            )
            evidence["v2_policy_detail_toggle"] = component_record(details_toggle)
            details_toggle.click()
            details = driver.wait_for_component(
                BY.id(V2_POLICY_DETAIL_CONTENT_ID), timeout=args.timeout
            )
            if details is None:
                raise RuntimeError("V2_POLICY_DETAILS_NOT_EXPANDED")
            evidence["v2_policy_details_expanded"] = component_record(details)
            details_toggle = wait_for_clickable(
                driver, BY.id(V2_POLICY_DETAIL_TOGGLE_ID), "V2_POLICY_DETAIL_TOGGLE_COLLAPSE", args.timeout
            )
            details_toggle.click()
            driver.wait_for_idle(idle_time=0.2, timeout=10)
            if driver.find_component(BY.id(V2_POLICY_DETAIL_CONTENT_ID)) is not None:
                raise RuntimeError("V2_POLICY_DETAILS_NOT_COLLAPSED")
            evidence["actions"].append("verify_v2_policy_details_expand_collapse")

        filter_input = driver.find_component(BY.id(SOURCE_FILTER_ID))
        if filter_input is None:
            search_action = wait_for_clickable(
                driver, BY.id(TITLE_SEARCH_ACTION_ID), "SOURCE_MANAGER_SEARCH_ACTION", args.timeout
            )
            evidence["source_manager_search_action"] = component_record(search_action)
            search_action.click()
            driver.wait_for_idle(idle_time=0.2, timeout=10)
            evidence["actions"].append("expand_source_manager_filter")
            filter_input = driver.wait_for_component(BY.id(SOURCE_FILTER_ID), timeout=args.timeout)
        else:
            evidence["actions"].append("reuse_expanded_source_filter")
        if filter_input is None:
            raise RuntimeError("SOURCE_MANAGER_FILTER_MISSING")
        if not filter_input.isEnabled():
            raise RuntimeError("SOURCE_MANAGER_FILTER_DISABLED")
        evidence["source_filter"] = component_record(filter_input)
        if args.safe_ui_audit:
            driver.clear_text(filter_input)
            driver.input_text(filter_input, "__MANXIA_UI_AUDIT_EMPTY__")
            driver.press_key(KeyCode.ENTER)
            empty_state = driver.wait_for_component(
                BY.id(SOURCE_MANAGEMENT_EMPTY_STATE_ID), timeout=args.timeout
            )
            if empty_state is None:
                raise RuntimeError("SAFE_UI_AUDIT_EMPTY_STATE_MISSING")
            evidence["source_management_empty_state"] = component_record(empty_state)
            empty_list_guide = driver.find_component(BY.id(SOURCE_LIST_GUIDE_ID))
            evidence["source_management_empty_list_guide_present"] = empty_list_guide is not None
            if empty_list_guide is not None:
                evidence["source_management_empty_list_guide"] = component_record(empty_list_guide)
                raise RuntimeError("SAFE_UI_AUDIT_EMPTY_LIST_GUIDE_VISIBLE")
            evidence["actions"].append("filter_management_to_empty_state_and_dismiss_keyboard")
            driver.wait_for_idle(idle_time=0.2, timeout=10)
            evidence["screenshots"]["source_management_safe"] = driver.capture_screen(
                str(output_dir / "03-source-management-safe.jpeg")
            )
            write_checkpoint(output_dir, evidence, "source_management_safe_captured")
        if args.source_id is not None and args.source_name is not None:
            driver.clear_text(filter_input)
            driver.input_text(filter_input, args.source_name)
            driver.wait_for_idle(idle_time=0.2, timeout=10)
            evidence["actions"].append("filter_source_card")
            filter_result_count = driver.wait_for_component(
                BY.id(SOURCE_FILTER_RESULT_COUNT_ID), timeout=args.timeout
            )
            if filter_result_count is None:
                raise RuntimeError("SOURCE_FILTER_RESULT_COUNT_MISSING")
            evidence["source_filter_result_count"] = component_record(filter_result_count)
            filter_result_text = filter_result_count.getText()
            filter_result_match = re.search(r"(\d+)", filter_result_text)
            if filter_result_match is None or int(filter_result_match.group(1)) <= 0:
                raise RuntimeError(
                    f"SOURCE_FILTER_NO_MATCH:{filter_result_text}"
                )
            # Source names are not a unique identity in a real imported pack;
            # several records can legitimately share the same display name.
            # The immutable source-id token on the card is the identity proof.
            # Keep the count as evidence, but do not reject a run merely because
            # the display-name filter returned multiple records.
            if filter_result_text != "1 项":
                evidence["source_filter_count_ambiguous"] = True
            evidence["actions"].append("verify_exact_source_filter_count")
            if args.filter_only:
                if args.verify_filter_trace_detail:
                    trace_detail_action = wait_for_clickable(
                        driver, BY.text("详情"), "SOURCE_TRACE_DETAIL_ACTION", args.timeout
                    )
                    trace_detail_action.click()
                    trace_detail_dialog = driver.wait_for_component(
                        BY.id(SOURCE_TRACE_DETAIL_DIALOG_ID), timeout=args.timeout
                    )
                    trace_detail_content = driver.wait_for_component(
                        BY.id(SOURCE_TRACE_DETAIL_CONTENT_ID), timeout=args.timeout
                    )
                    if trace_detail_dialog is None or trace_detail_content is None:
                        raise RuntimeError("SOURCE_TRACE_DETAIL_DIALOG_MISSING")
                    if "trace" not in trace_detail_content.getText().lower():
                        raise RuntimeError("SOURCE_TRACE_DETAIL_CONTENT_INVALID")
                    evidence["source_trace_detail_dialog"] = component_record(trace_detail_dialog)
                    evidence["source_trace_detail_content"] = component_record(trace_detail_content)
                    if args.capture_visual_evidence:
                        evidence["screenshots"]["source_trace_detail"] = driver.capture_screen(
                            str(output_dir / "03-source-trace-detail.jpeg")
                        )
                    trace_detail_close = wait_for_clickable(
                        driver, BY.id(SOURCE_TRACE_DETAIL_CLOSE_ID), "SOURCE_TRACE_DETAIL_CLOSE", args.timeout
                    )
                    trace_detail_close.click()
                    driver.wait_for_idle(idle_time=0.2, timeout=10)
                    if driver.find_component(BY.id(SOURCE_TRACE_DETAIL_DIALOG_ID)) is not None:
                        raise RuntimeError("SOURCE_TRACE_DETAIL_DIALOG_NOT_CLOSED")
                    evidence["actions"].append("verify_source_trace_detail_open_close")
                if args.capture_visual_evidence:
                    evidence["screenshots"]["exact_source_filter"] = driver.capture_screen(
                        str(output_dir / "03-exact-source-filter.jpeg")
                    )
                evidence["status"] = "passed"
                evidence["actions"].append("complete_exact_source_filter_only")
                write_checkpoint(output_dir, evidence, "exact_source_filter_verified")
                return 0
            source_token = source_automation_token(args.source_id)
            source_card = wait_for_clickable_with_bounded_scroll(
                driver,
                BY.id(f"novel_source_card_{source_token}"),
                "SOURCE_CARD",
                args.timeout,
                evidence,
                scroll_target=BY.type("Scroll"),
            )
            evidence["source_card"] = component_record(source_card, redact_source_identity=True)
            evidence["v2_compile_diagnostic_codes"] = read_source_compile_diagnostic_codes(
                driver, BY, source_token
            )
            source_card.click()
            driver.wait_for_idle(idle_time=0.2, timeout=10)
            evidence["actions"].append("open_single_source_search")
            single_source_input = driver.wait_for_component(
                BY.id(SEARCH_INPUT_ID), timeout=args.timeout
            )
            if single_source_input is None:
                raise RuntimeError("SINGLE_SOURCE_SEARCH_INPUT_MISSING")
            if not single_source_input.isEnabled():
                raise RuntimeError("SINGLE_SOURCE_SEARCH_INPUT_DISABLED")
            source_identity = driver.wait_for_component(
                BY.id(f"novel_search_single_source_{source_token}"), timeout=args.timeout
            )
            if source_identity is None:
                raise RuntimeError("SINGLE_SOURCE_IDENTITY_MISMATCH")
            evidence["single_source_identity"] = component_record(
                source_identity, redact_source_identity=True
            )
            evidence["single_source_search_input"] = component_record(single_source_input)
            write_checkpoint(output_dir, evidence, "single_source_search_ready")
            if args.search_keyword is not None:
                driver.clear_text(single_source_input)
                driver.input_text(single_source_input, args.search_keyword)
                search_submit = wait_for_clickable(
                    driver, BY.id(SEARCH_SUBMIT_ID), "SEARCH_SUBMIT", args.timeout
                )
                search_submit.click()
                evidence["actions"].append("submit_authorized_search")
                write_checkpoint(output_dir, evidence, "search_submitted")
                outcome = wait_for_search_outcome(driver, BY, args.package, args.timeout)
                evidence["search_outcome"] = outcome
                evidence["foreground_bundle_after_search"] = current_bundle_name(driver)
                if outcome == "execution_failure":
                    error_category = get_search_error_category(driver, BY)
                    if error_category:
                        evidence["search_error_category"] = error_category
                result_container = driver.find_component(BY.id(SEARCH_RESULTS_ID))
                if result_container is not None:
                    evidence["single_source_result_container"] = component_record(result_container)
                write_checkpoint(output_dir, evidence, "search_outcome_recorded")
                if outcome == "app_exited":
                    evidence["search_error_category"] = "app_exited"
                    raise RuntimeError("APP_EXITED_AFTER_SEARCH")
                trace_toggle = driver.find_component(BY.id(SEARCH_TRACE_TOGGLE_ID))
                if trace_toggle is not None:
                    if not trace_toggle.isEnabled() or not trace_toggle.isClickable():
                        raise RuntimeError("SEARCH_TRACE_TOGGLE_NOT_ACTIONABLE")
                    trace_toggle.click()
                    evidence["actions"].append("expand_search_trace")
                    trace_detail = driver.wait_for_component(
                        BY.id(SEARCH_TRACE_DETAIL_ID), timeout=args.timeout
                    )
                    if trace_detail is None:
                        raise RuntimeError("SEARCH_TRACE_DETAIL_MISSING")
                    evidence["single_source_trace"] = component_record(trace_detail)
                # The result route owns the immutable trace for this exact
                # request. Capture it before navigation can recreate the
                # management page and replace a reactive card snapshot.
                evidence["trace_records"] = wait_for_sanitized_trace_records(
                    driver, BY, args.source_id, args.package, args.timeout
                )
                write_checkpoint(output_dir, evidence, "search_trace_captured")
                if args.safe_read_path and outcome == "result" and args.source_id is not None:
                    execute_safe_read_path(
                        driver,
                        BY,
                        args.source_id,
                        args.package,
                        args.timeout,
                        evidence,
                        image_workflow=args.image_workflow,
                        hdc_path=args.hdc_path,
                    )
                    write_checkpoint(output_dir, evidence, "reader_content_captured")
                else:
                    evidence["return_route"] = return_to_source_management(driver, BY, args.timeout)
                    evidence["actions"].append("return_source_management")
        if args.capture_visual_evidence and not args.safe_read_path and not args.safe_ui_audit:
            evidence["screenshots"]["source_management"] = driver.capture_screen(
                str(output_dir / "03-source-management.jpeg")
            )
        evidence["status"] = "passed"
        write_checkpoint(output_dir, evidence, "completed")
        exit_code = 0
    except Exception as exc:
        evidence["error"] = f"{type(exc).__name__}: {exc}"
        if driver is not None and "BY" in locals():
            try:
                evidence["reader_diagnostic_snapshot"] = reader_diagnostic_snapshot(
                    driver,
                    BY,
                    args.package,
                    output_dir,
                    args.capture_visual_evidence and not args.safe_read_path and not args.safe_ui_audit,
                )
            except Exception as diagnostic_error:
                evidence["reader_diagnostic_snapshot_error"] = (
                    f"{type(diagnostic_error).__name__}: {diagnostic_error}"
                )
        write_checkpoint(output_dir, evidence, "exception")
        if driver is not None:
            try:
                if args.capture_visual_evidence and not args.safe_ui_audit:
                    evidence["screenshots"]["failure"] = driver.capture_screen(
                        str(output_dir / "failure.jpeg")
                    )
            except Exception as capture_error:
                evidence["failure_screenshot_error"] = (
                    f"{type(capture_error).__name__}: {capture_error}"
                )
        write_checkpoint(output_dir, evidence, "failure_captured")
    finally:
        if driver is not None:
            if not args.leave_app:
                try:
                    driver.go_home()
                    evidence["actions"].append("restore_home")
                except Exception as home_error:
                    evidence["restore_home_error"] = f"{type(home_error).__name__}: {home_error}"
            try:
                driver.close()
                evidence["driver_closed"] = True
            except Exception as close_error:
                evidence["close_error"] = f"{type(close_error).__name__}: {close_error}"
                exit_code = 1
        write_evidence(output_dir, evidence)
    return exit_code


def main() -> int:
    args = parse_arguments()
    if args.parser_self_test:
        print(json.dumps(run_trace_parser_contract(), ensure_ascii=True, sort_keys=True))
        return 0
    if args.image_explore_contract_self_test:
        print(json.dumps(run_image_explore_harness_contract(), ensure_ascii=True, sort_keys=True))
        return 0
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
