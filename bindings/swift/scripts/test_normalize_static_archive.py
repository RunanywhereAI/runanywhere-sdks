#!/usr/bin/env python3
"""Focused regression tests for deterministic Apple archive member names."""

from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parent / "normalize-static-archive.py"


def _field(value: str, width: int) -> bytes:
    encoded = value.encode("ascii")
    if len(encoded) > width:
        raise ValueError(f"field {value!r} exceeds {width} bytes")
    return encoded.ljust(width, b" ")


def _archive(path: Path, members: list[tuple[str, bytes]]) -> None:
    payload = bytearray(b"!<arch>\n")
    for name, member_payload in members:
        encoded_name = name.encode("ascii") + b"\0"
        member_size = len(encoded_name) + len(member_payload)
        payload.extend(_field(f"#1/{len(encoded_name)}", 16))
        payload.extend(_field("0", 12))
        payload.extend(_field("0", 6))
        payload.extend(_field("0", 6))
        payload.extend(_field("100644", 8))
        payload.extend(_field(str(member_size), 10))
        payload.extend(b"`\n")
        payload.extend(encoded_name)
        payload.extend(member_payload)
        if member_size % 2:
            payload.extend(b"\n")
    path.write_bytes(payload)


def _run(path: Path, *expected: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["python3", str(SCRIPT), str(path), *expected],
        check=False,
        capture_output=True,
        text=True,
        timeout=5,
    )


class StaticArchiveNormalizerTest(unittest.TestCase):
    def test_path_derived_names_become_byte_identical(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            first = root / "first.a"
            second = root / "second.a"
            payloads = (b"first object payload", b"second object payload")
            _archive(
                first,
                [
                    ("stable.o", b"stable"),
                    ("parser-11111111111111111111111111111111.o", payloads[0]),
                    ("parser-22222222222222222222222222222222.o", payloads[1]),
                ],
            )
            _archive(
                second,
                [
                    ("stable.o", b"stable"),
                    ("parser-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.o", payloads[0]),
                    ("parser-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.o", payloads[1]),
                ],
            )

            first_result = _run(first, "parser=2")
            second_result = _run(second, "parser=2")
            self.assertEqual(first_result.returncode, 0, first_result.stderr)
            self.assertEqual(second_result.returncode, 0, second_result.stderr)
            self.assertIn("normalized 2", first_result.stdout)
            self.assertEqual(first.read_bytes(), second.read_bytes())

            digest = hashlib.sha256(first.read_bytes()).hexdigest()
            repeated = _run(first, "parser=2")
            self.assertEqual(repeated.returncode, 0, repeated.stderr)
            self.assertEqual(repeated.stdout, "")
            self.assertEqual(hashlib.sha256(first.read_bytes()).hexdigest(), digest)

    def test_rejects_invalid_archive(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            archive = root / "invalid.a"
            archive.write_bytes(b"not an archive")
            result = _run(archive)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid static archive magic", result.stderr)

            for index, member_size in enumerate(("", "-60")):
                malformed = root / f"invalid-size-{index}.a"
                malformed.write_bytes(
                    b"!<arch>\n"
                    + _field("member.o/", 16)
                    + _field("0", 12)
                    + _field("0", 6)
                    + _field("0", 6)
                    + _field("100644", 8)
                    + _field(member_size, 10)
                    + b"`\n"
                )
                result = _run(malformed)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("invalid member size field", result.stderr)

            empty_extended_name = root / "invalid-extended-name.a"
            empty_extended_name.write_bytes(
                b"!<arch>\n"
                + _field("#1/0", 16)
                + _field("0", 12)
                + _field("0", 6)
                + _field("0", 6)
                + _field("100644", 8)
                + _field("0", 10)
                + b"`\n"
            )
            result = _run(empty_extended_name)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid extended member name", result.stderr)

            invalid_padding = root / "invalid-padding.a"
            invalid_padding.write_bytes(
                b"!<arch>\n"
                + _field("member.o/", 16)
                + _field("0", 12)
                + _field("0", 6)
                + _field("0", 6)
                + _field("100644", 8)
                + _field("1", 10)
                + b"`\n"
                + b"x\0"
            )
            result = _run(invalid_padding)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid member padding", result.stderr)

    def test_rejects_unreviewed_hashed_stem_or_count(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            archive = root / "unexpected.a"
            _archive(
                archive,
                [("upstream-cccccccccccccccccccccccccccccccc.o", b"payload")],
            )
            result = _run(archive)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("hashed member inventory changed", result.stderr)

            count_mismatch = root / "count-mismatch.a"
            _archive(
                count_mismatch,
                [("parser-dddddddddddddddddddddddddddddddd.o", b"payload")],
            )
            result = _run(count_mismatch, "parser=2")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("expected parser=2; found parser=1", result.stderr)

    def test_zero_inventory_accepts_unhashed_archive(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            archive = Path(temporary_directory) / "stable.a"
            _archive(archive, [("stable.o", b"payload")])
            result = _run(archive)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
