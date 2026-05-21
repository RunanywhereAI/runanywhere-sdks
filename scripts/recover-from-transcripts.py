#!/usr/bin/env python3
"""Replay Write/StrReplace tool ops from Cursor agent transcripts onto the repo."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[1]
TRANSCRIPTS = Path.home() / ".cursor/projects/Users-sanchitmonga-development-ODLM-MONOREPOOO-runanywhere-sdks3-runanywhere-sdks-main/agent-transcripts"

TARGET_SUFFIXES = {
    "sdk/runanywhere-react-native/packages/core/src/services/ProtoWire.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/RunAnywhere.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/Events/RunAnywhere+SDKEvents.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/LLM/RunAnywhere+LoRA.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/LLM/RunAnywhere+StructuredOutput.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/LLM/RunAnywhere+TextGeneration.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/LLM/RunAnywhere+ToolCalling.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/Models/RunAnywhere+ModelLifecycle.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/Models/RunAnywhere+ModelRegistry.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/RAG/RunAnywhere+RAG.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/RunAnywhere+Hardware.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/STT/RunAnywhere+STT.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/Solutions/RunAnywhere+Solutions.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/Storage/RunAnywhere+Storage.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/TTS/RunAnywhere+TTS.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/VAD/RunAnywhere+VAD.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/VLM/RunAnywhere+VisionLanguage.ts",
    "sdk/runanywhere-react-native/packages/core/src/Public/Extensions/VoiceAgent/RunAnywhere+VoiceAgent.ts",
    "sdk/runanywhere-flutter/packages/runanywhere/lib/native/dart_bridge.dart",
    "sdk/runanywhere-flutter/packages/runanywhere/lib/native/dart_bridge_model_registry.dart",
    "examples/flutter/RunAnywhereAI/lib/app/runanywhere_ai_app.dart",
    "examples/flutter/RunAnywhereAI/lib/features/voice/text_to_speech_view.dart",
    "examples/flutter/RunAnywhereAI/lib/features/voice/voice_assistant_view.dart",
    "examples/react-native/RunAnywhereAI/android/app/src/main/res/raw/keep.xml",
    "examples/react-native/RunAnywhereAI/ios/RunAnywhereAI.xcodeproj/project.pbxproj",
    "examples/react-native/RunAnywhereAI/metro.config.js",
    "examples/react-native/RunAnywhereAI/package.json",
    "package.json",
    "yarn.lock",
    "scripts/build-core-xcframework.sh",
}


@dataclass
class Op:
    order: int
    tool: str
    rel_path: str
    payload: dict[str, Any]
    source: str


def normalize_path(raw: str) -> str | None:
    raw = raw.replace("\\", "/")
    marker = "/runanywhere-sdks-main/"
    if marker in raw:
        raw = raw.split(marker, 1)[1]
    elif raw.startswith(str(REPO)):
        raw = os.path.relpath(raw, REPO)
    rel = raw.lstrip("./")
    if rel in TARGET_SUFFIXES:
        return rel
    return None


def git_show(rel: str) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "show", f"HEAD:{rel}"],
            cwd=REPO,
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        return None


def collect_ops() -> list[Op]:
    ops: list[Op] = []
    order = 0
    for jsonl in sorted(TRANSCRIPTS.rglob("*.jsonl")):
        try:
            lines = jsonl.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            content = row.get("message", {}).get("content")
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                name = block.get("name")
                if name not in {"Write", "StrReplace"}:
                    continue
                inp = block.get("input") or {}
                rel = normalize_path(str(inp.get("path", "")))
                if not rel:
                    continue
                ops.append(
                    Op(
                        order=order,
                        tool=name,
                        rel_path=rel,
                        payload=inp,
                        source=str(jsonl.relative_to(TRANSCRIPTS)),
                    )
                )
                order += 1
    return ops


def apply_ops(ops: list[Op]) -> dict[str, list[str]]:
    by_file: dict[str, list[Op]] = {}
    for op in ops:
        by_file.setdefault(op.rel_path, []).append(op)

    report: dict[str, list[str]] = {}
    for rel, file_ops in sorted(by_file.items()):
        log: list[str] = []
        abs_path = REPO / rel
        if file_ops[0].tool == "Write" and file_ops[0].payload.get("contents") is not None:
            text = file_ops[0].payload["contents"]
            log.append(f"init Write ({file_ops[0].source})")
        else:
            text = git_show(rel)
            if text is None:
                text = ""
            log.append("init from git HEAD" if text else "init empty (new file)")

        applied = 0
        skipped = 0
        for op in file_ops:
            if op.tool == "Write":
                if op.payload.get("contents") is not None:
                    text = op.payload["contents"]
                    applied += 1
                    log.append(f"Write applied ({op.source})")
                continue
            old = op.payload.get("old_string")
            new = op.payload.get("new_string")
            if not isinstance(old, str) or not isinstance(new, str):
                skipped += 1
                continue
            if old not in text:
                skipped += 1
                log.append(f"SKIP StrReplace — old_string not found ({op.source})")
                continue
            text = text.replace(old, new, 1)
            applied += 1
            log.append(f"StrReplace applied ({op.source})")

        abs_path.parent.mkdir(parents=True, exist_ok=True)
        abs_path.write_text(text, encoding="utf-8")
        log.insert(0, f"{applied} applied, {skipped} skipped, {len(text.splitlines())} lines")
        report[rel] = log
    return report


def main() -> int:
    if not TRANSCRIPTS.is_dir():
        print(f"Transcripts not found: {TRANSCRIPTS}", file=sys.stderr)
        return 1

    ops = collect_ops()
    print(f"Collected {len(ops)} ops across {len({o.rel_path for o in ops})} target files")
    report = apply_ops(ops)

    missing = sorted(TARGET_SUFFIXES - set(report))
    print("\n=== RECOVERED ===")
    for rel, lines in sorted(report.items()):
        print(f"\n{rel}")
        for line in lines:
            print(f"  {line}")

    if missing:
        print("\n=== NOT FOUND IN TRANSCRIPTS (manual follow-up) ===")
        for rel in missing:
            print(f"  {rel}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
