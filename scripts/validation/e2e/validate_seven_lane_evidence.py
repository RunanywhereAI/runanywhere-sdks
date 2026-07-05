#!/usr/bin/env python3
"""Validate seven-lane runtime evidence shape.

This checker validates the evidence contract, not runtime correctness. It is
safe to run on a dry-run folder that contains only synthetic BLOCKED evidence.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path


LANES = {
    "01_android_kotlin": ("Kotlin", "Android"),
    "02_ios_swift": ("Swift", "iOS"),
    "03_react_native_android": ("React Native", "Android"),
    "04_react_native_ios": ("React Native", "iOS"),
    "05_flutter_android": ("Flutter", "Android"),
    "06_flutter_ios": ("Flutter", "iOS"),
    "07_web": ("Web", "Browser"),
}

STATUSES = {"PASS", "FAIL", "BLOCKED", "LIMITED", "N/A", "SMOKE_PASS"}
YES_NO_NA = {"yes", "no", "n/a"}

ROOT_SUMMARY_HEADER = ["name", "status", "exit_code", "log"]
COMMAND_SUMMARY_HEADER = ["name", "status", "exit_code", "log"]
FAILURE_SUMMARY_HEADER = [
    "id",
    "lane",
    "modality",
    "severity",
    "evidence",
    "summary",
    "owner_area",
    "next_action",
]
MODALITY_HEADER = [
    "modality",
    "status",
    "model_id",
    "downloaded",
    "loaded",
    "inference_run",
    "output_evidence",
    "logs_reviewed",
    "log_paths",
    "screenshots",
    "notes",
]
ACTION_KEYS = [
    "ts",
    "target",
    "sdk",
    "platform",
    "modality",
    "phase",
    "action",
    "expected",
    "actual",
    "status",
    "screenshot",
    "logs",
    "modelId",
    "notes",
]
REQUIRED_ACTION_PHASES = {
    "clean_install",
    "model_download",
    "model_load",
    "inference",
    "modality_result",
}
OPTIONAL_ACTION_PHASES = {
    "build",
    "launch",
    "logging",
    "cleanup",
    "blocked_prereq",
    "other",
}
ACTION_PHASES = REQUIRED_ACTION_PHASES | OPTIONAL_ACTION_PHASES


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate seven-lane validation evidence schema."
    )
    parser.add_argument("run_dir", type=Path, help="Run folder to validate.")
    parser.add_argument(
        "--require-evidence",
        action="store_true",
        help="Require each lane to contain action and modality rows.",
    )
    parser.add_argument(
        "--require-files",
        action="store_true",
        help="Require referenced screenshot and log files to exist.",
    )
    return parser.parse_args()


def read_header(path: Path) -> list[str] | None:
    if not path.exists():
        return None
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle, delimiter="\t")
        return next(reader, None)


def read_tsv(path: Path) -> tuple[list[str] | None, list[dict[str, str]]]:
    if not path.exists():
        return None, []
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        return reader.fieldnames, list(reader)


def split_paths(value: str) -> list[str]:
    return [part.strip() for part in value.split(";") if part.strip()]


def validate_relative_path(
    errors: list[str],
    lane_dir: Path,
    field_name: str,
    value: str,
    expected_prefix: str,
    require_files: bool,
) -> None:
    if not value:
        errors.append(f"{lane_dir.name}: {field_name} is empty")
        return

    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        errors.append(f"{lane_dir.name}: {field_name} must be a lane-relative path: {value}")
        return

    if path.parts[0] != expected_prefix:
        errors.append(
            f"{lane_dir.name}: {field_name} must be under {expected_prefix}/: {value}"
        )
        return

    if require_files and not (lane_dir / path).exists():
        errors.append(f"{lane_dir.name}: referenced {field_name} does not exist: {value}")


def validate_command_summary(
    errors: list[str], lane_dir: Path, require_evidence: bool, require_files: bool
) -> None:
    path = lane_dir / "command_summary.tsv"
    header, rows = read_tsv(path)
    if header is None:
        errors.append(f"{lane_dir.name}: missing command_summary.tsv")
        return
    if header != COMMAND_SUMMARY_HEADER:
        errors.append(
            f"{lane_dir.name}: command_summary.tsv header mismatch: {header}"
        )
        return
    if require_evidence and not rows:
        errors.append(f"{lane_dir.name}: command_summary.tsv has no evidence rows")
    for index, row in enumerate(rows, start=2):
        if row.get("status") and row["status"] not in STATUSES:
            errors.append(
                f"{lane_dir.name}: command_summary.tsv line {index} invalid status {row['status']}"
            )
        log = row.get("log", "")
        if log:
            validate_relative_path(
                errors, lane_dir, f"command_summary.tsv line {index} log", log, "logs", require_files
            )


def validate_actions(
    errors: list[str],
    lane_dir: Path,
    lane: str,
    sdk: str,
    platform: str,
    require_evidence: bool,
    require_files: bool,
) -> None:
    path = lane_dir / "actions.jsonl"
    if not path.exists():
        errors.append(f"{lane}: missing actions.jsonl")
        return

    action_count = 0
    phases: set[str] = set()
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        action_count += 1
        try:
            item = json.loads(line)
        except json.JSONDecodeError as exc:
            errors.append(f"{lane}: actions.jsonl line {line_number} invalid JSON: {exc}")
            continue
        if not isinstance(item, dict):
            errors.append(f"{lane}: actions.jsonl line {line_number} is not an object")
            continue

        missing = [key for key in ACTION_KEYS if key not in item]
        if missing:
            errors.append(
                f"{lane}: actions.jsonl line {line_number} missing keys: {', '.join(missing)}"
            )
            continue

        for key in ACTION_KEYS:
            if key == "logs":
                continue
            if not isinstance(item[key], str) or not item[key].strip():
                errors.append(
                    f"{lane}: actions.jsonl line {line_number} {key} must be a non-empty string"
                )

        if item["target"] != lane:
            errors.append(
                f"{lane}: actions.jsonl line {line_number} target mismatch: {item['target']}"
            )
        if item["sdk"] != sdk:
            errors.append(
                f"{lane}: actions.jsonl line {line_number} sdk mismatch: {item['sdk']}"
            )
        if item["platform"] != platform:
            errors.append(
                f"{lane}: actions.jsonl line {line_number} platform mismatch: {item['platform']}"
            )
        if item["status"] not in STATUSES:
            errors.append(
                f"{lane}: actions.jsonl line {line_number} invalid status: {item['status']}"
            )

        phase = item["phase"]
        if phase not in ACTION_PHASES:
            errors.append(
                f"{lane}: actions.jsonl line {line_number} invalid phase: {phase}"
            )
        phases.add(phase)

        if not isinstance(item["logs"], list) or not item["logs"]:
            errors.append(f"{lane}: actions.jsonl line {line_number} logs must be a non-empty array")
        else:
            for log_index, log_path in enumerate(item["logs"], start=1):
                if not isinstance(log_path, str):
                    errors.append(
                        f"{lane}: actions.jsonl line {line_number} logs[{log_index}] is not a string"
                    )
                    continue
                validate_relative_path(
                    errors,
                    lane_dir,
                    f"actions.jsonl line {line_number} logs[{log_index}]",
                    log_path,
                    "logs",
                    require_files,
                )

        if not isinstance(item["screenshot"], str):
            errors.append(f"{lane}: actions.jsonl line {line_number} screenshot is not a string")
        else:
            validate_relative_path(
                errors,
                lane_dir,
                f"actions.jsonl line {line_number} screenshot",
                item["screenshot"],
                "screenshots",
                require_files,
            )

    if require_evidence and action_count == 0:
        errors.append(f"{lane}: actions.jsonl has no evidence rows")

    if require_evidence:
        missing_phases = sorted(REQUIRED_ACTION_PHASES - phases)
        if missing_phases:
            errors.append(
                f"{lane}: actions.jsonl missing required phases: {', '.join(missing_phases)}"
            )


def validate_modality_table(
    errors: list[str],
    lane_dir: Path,
    lane: str,
    require_evidence: bool,
    require_files: bool,
) -> None:
    path = lane_dir / "modality_table.tsv"
    header, rows = read_tsv(path)
    if header is None:
        errors.append(f"{lane}: missing modality_table.tsv")
        return
    if header != MODALITY_HEADER:
        errors.append(f"{lane}: modality_table.tsv header mismatch: {header}")
        return

    if require_evidence and not rows:
        errors.append(f"{lane}: modality_table.tsv has no evidence rows")

    for index, row in enumerate(rows, start=2):
        status = row.get("status", "")
        if status not in STATUSES:
            errors.append(f"{lane}: modality_table.tsv line {index} invalid status: {status}")

        for key in ("downloaded", "loaded", "inference_run", "logs_reviewed"):
            value = row.get(key, "")
            if value not in YES_NO_NA:
                errors.append(
                    f"{lane}: modality_table.tsv line {index} {key} must be yes/no/n/a: {value}"
                )

        if status == "PASS":
            for key in ("downloaded", "loaded", "inference_run", "logs_reviewed"):
                if row.get(key) != "yes":
                    errors.append(
                        f"{lane}: modality_table.tsv line {index} PASS requires {key}=yes"
                    )

        for log_path in split_paths(row.get("log_paths", "")):
            validate_relative_path(
                errors,
                lane_dir,
                f"modality_table.tsv line {index} log_paths",
                log_path,
                "logs",
                require_files,
            )
        for screenshot in split_paths(row.get("screenshots", "")):
            validate_relative_path(
                errors,
                lane_dir,
                f"modality_table.tsv line {index} screenshots",
                screenshot,
                "screenshots",
                require_files,
            )

        if row.get("logs_reviewed") == "yes" and not split_paths(row.get("log_paths", "")):
            errors.append(
                f"{lane}: modality_table.tsv line {index} logs_reviewed=yes requires log_paths"
            )
        if status != "N/A" and not split_paths(row.get("screenshots", "")):
            errors.append(
                f"{lane}: modality_table.tsv line {index} non-N/A row requires screenshots"
            )


def validate_root(errors: list[str], run_dir: Path) -> None:
    for name in ("RUN_MANIFEST.md", "REPORT.md", "summary.tsv", "failure_summary.tsv", "machine_summary.json"):
        if not (run_dir / name).exists():
            errors.append(f"missing root file: {name}")

    summary_header = read_header(run_dir / "summary.tsv")
    if summary_header != ROOT_SUMMARY_HEADER:
        errors.append(f"summary.tsv header mismatch: {summary_header}")

    failure_header = read_header(run_dir / "failure_summary.tsv")
    if failure_header != FAILURE_SUMMARY_HEADER:
        errors.append(f"failure_summary.tsv header mismatch: {failure_header}")

    machine_summary = run_dir / "machine_summary.json"
    if machine_summary.exists():
        try:
            data = json.loads(machine_summary.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"machine_summary.json invalid JSON: {exc}")
        else:
            if data.get("evidence_schema_version") != 2:
                errors.append("machine_summary.json evidence_schema_version must be 2")

    if not (run_dir / "global" / "logs").is_dir():
        errors.append("missing global/logs directory")


def main() -> int:
    args = parse_args()
    run_dir = args.run_dir.resolve()
    errors: list[str] = []

    if not run_dir.exists():
        print(f"run dir does not exist: {run_dir}", file=sys.stderr)
        return 2

    validate_root(errors, run_dir)

    for lane, (sdk, platform) in LANES.items():
        lane_dir = run_dir / lane
        if not lane_dir.is_dir():
            errors.append(f"missing lane directory: {lane}")
            continue
        for child in ("logs", "screenshots", "videos"):
            if not (lane_dir / child).is_dir():
                errors.append(f"{lane}: missing {child}/ directory")
        if not (lane_dir / "agent_report.md").exists():
            errors.append(f"{lane}: missing agent_report.md")
        validate_command_summary(
            errors, lane_dir, args.require_evidence, args.require_files
        )
        validate_actions(
            errors,
            lane_dir,
            lane,
            sdk,
            platform,
            args.require_evidence,
            args.require_files,
        )
        validate_modality_table(
            errors, lane_dir, lane, args.require_evidence, args.require_files
        )

    # Count per-lane validation results for the summary line.
    lane_count = 0
    lane_pass_count = 0
    for lane in LANES:
        lane_dir = run_dir / lane
        if not lane_dir.is_dir():
            continue
        lane_count += 1
        lane_has_error = any(e.startswith(f"{lane}:") or e.startswith(f"missing lane directory: {lane}") for e in errors)
        if not lane_has_error:
            lane_pass_count += 1

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        # Brief summary to stdout so the shell script can capture it.
        print(f"seven-lane evidence schema: FAIL ({len(errors)} errors, {lane_pass_count}/{lane_count} lanes clean)")
        print(f"seven-lane evidence schema: FAIL ({len(errors)} errors)", file=sys.stderr)
        return 1

    # Brief summary to stdout so the shell script can capture it.
    print(f"seven-lane evidence schema: PASS ({lane_count}/{lane_count} lanes clean)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
