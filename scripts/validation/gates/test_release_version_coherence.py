"""Tests for the podspec source-tag half of check_release_version_coherence.sh.

The gate is the only thing standing between a podspec and a `:tag` that was
never pushed, which fails `pod install` outright rather than degrading. It reads
~40 files under REPO_ROOT, so the tests run it against a sandbox that mirrors
the real tree with symlinks and materializes only the podspecs a case mutates.
That keeps every other assertion in the gate satisfied by the real repo, so a
failure means the mutation caused it.
"""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


REPO_ROOT = Path(__file__).resolve().parents[3]
GATE = "scripts/validation/gates/check_release_version_coherence.sh"

RN_PODSPECS = (
    "bindings/react-native/packages/core/RunAnywhereCore.podspec",
    "bindings/react-native/packages/llamacpp/RunAnywhereLlama.podspec",
    "bindings/react-native/packages/mlx/RunAnywhereMLX.podspec",
    "bindings/react-native/packages/onnx/RunAnywhereONNX.podspec",
)


def _mirror(tmp_path, writable, case="case"):
    """Symlink-mirror REPO_ROOT into a fresh sandbox, copying `writable` for real.

    Only the directories on the path to a writable file become real; every
    other entry is a symlink to the original, so the mirror costs nothing.
    Returns the sandbox root, which is what the gate sees as REPO_ROOT.
    """
    sandbox = tmp_path / case
    real_dirs = set()
    for relative in writable:
        parent = os.path.dirname(relative)
        while parent:
            real_dirs.add(parent)
            parent = os.path.dirname(parent)

    def build(relative):
        source = REPO_ROOT / relative if relative else REPO_ROOT
        target = sandbox / relative if relative else sandbox
        target.mkdir(parents=True, exist_ok=True)
        for child in source.iterdir():
            child_relative = f"{relative}/{child.name}" if relative else child.name
            if child_relative in writable:
                shutil.copy2(child, target / child.name)
            elif child_relative in real_dirs:
                build(child_relative)
            else:
                (target / child.name).symlink_to(child)

    build("")
    return sandbox


def _run(sandbox):
    return subprocess.run(
        ["bash", os.fspath(sandbox / GATE)],
        capture_output=True,
        text=True,
        # PR_BASE_SHA would pull the gate into its release-label branch, which
        # needs a real git base and is not what these cases are about.
        env={k: v for k, v in os.environ.items() if k != "PR_BASE_SHA"},
    )


def _spm_version():
    for line in (REPO_ROOT / "Package.swift").read_text(encoding="utf-8").splitlines():
        if line.startswith('let sdkVersion = "'):
            return line.split('"')[1]
    raise AssertionError("Package.swift has no sdkVersion pin")


def test_unmodified_tree_passes(tmp_path):
    # Establishes the baseline the other cases lean on: whatever they trip, it
    # is not one of the gate's other forty assertions.
    sandbox = _mirror(tmp_path, writable=set())
    result = _run(sandbox)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "[OK] release version coherence" in result.stdout


def test_source_tag_built_from_s_version_is_rejected(tmp_path):
    # The original defect. s.version tracks package.json, which leads the last
    # tagged release whenever a release republishes only some packages, so a tag
    # interpolated from it resolves to one that was never pushed.
    for index, podspec in enumerate(RN_PODSPECS):
        sandbox = _mirror(tmp_path, writable={podspec}, case=f"case{index}")
        text = (sandbox / podspec).read_text(encoding="utf-8")
        (sandbox / podspec).write_text(
            text.replace('"v#{source_tag_version}"', '"v#{s.version}"'), encoding="utf-8"
        )
        result = _run(sandbox)
        assert result.returncode == 1, podspec
        assert "source tag interpolates s.version" in result.stderr, podspec


def test_source_tag_pinned_to_the_wrong_release_is_rejected(tmp_path):
    # Pinning is not enough on its own: the pin has to be the same release the
    # SwiftPM manifests resolve their XCFrameworks from, or the podspec points
    # at a tag whose assets belong to a different build.
    podspec = RN_PODSPECS[0]
    sandbox = _mirror(tmp_path, writable={podspec})
    text = (sandbox / podspec).read_text(encoding="utf-8")
    assert f"source_tag_version = '{_spm_version()}'" in text
    (sandbox / podspec).write_text(
        text.replace(f"source_tag_version = '{_spm_version()}'", "source_tag_version = '0.0.1'"),
        encoding="utf-8",
    )
    result = _run(sandbox)
    assert result.returncode == 1
    assert f"expected 'source_tag_version = '{_spm_version()}''" in result.stderr


def test_every_rn_podspec_is_covered(tmp_path):
    # The Flutter podspecs were already gated when this drifted; RN was simply
    # not in the loop. A podspec added later and left out of the gate's list is
    # the same failure again, so assert the list is the directory.
    gate = (REPO_ROOT / GATE).read_text(encoding="utf-8")
    on_disk = sorted(
        str(p.relative_to(REPO_ROOT))
        for p in (REPO_ROOT / "bindings/react-native/packages").glob("*/*.podspec")
    )
    assert on_disk == sorted(RN_PODSPECS)
    for podspec in on_disk:
        assert podspec in gate, f"{podspec} is not covered by {GATE}"


if __name__ == "__main__":
    tests = sorted(
        (name, value)
        for name, value in globals().items()
        if name.startswith("test_") and callable(value)
    )
    for name, test in tests:
        with tempfile.TemporaryDirectory(prefix=f"{name}-") as temporary:
            test(Path(temporary))
    print(f"{len(tests)} release version coherence tests passed", file=sys.stderr)
