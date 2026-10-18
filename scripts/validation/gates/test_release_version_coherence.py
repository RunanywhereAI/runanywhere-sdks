"""Tests for the podspec source-tag and root README pin halves of
check_release_version_coherence.sh.

The gate is the only thing standing between a podspec and a `:tag` that was
never pushed, which fails `pod install` outright rather than degrading. It reads
~40 files under REPO_ROOT, so the tests run it against a sandbox that mirrors
the real tree with symlinks and materializes only the files a case mutates.
That keeps every other assertion in the gate satisfied by the real repo, so a
failure means the mutation caused it.
"""

import os
from pathlib import Path
import re
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


def _core_version():
    return (REPO_ROOT / "core/VERSION").read_text(encoding="utf-8").strip()


def _readme_pin_version():
    # The registry pins follow core/VERSION unless a TEMP marker holds them on
    # the last published version.
    match = re.search(
        r"TEMP: install pins stay on (\S+) until v",
        (REPO_ROOT / "README.md").read_text(encoding="utf-8"),
    )
    return match.group(1) if match else _core_version()


def _mutate_readme(tmp_path, old, new):
    sandbox = _mirror(tmp_path, writable={"README.md"})
    text = (sandbox / "README.md").read_text(encoding="utf-8")
    assert text.count(old) == 1, old
    (sandbox / "README.md").write_text(text.replace(old, new), encoding="utf-8")
    return _run(sandbox)


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


def test_one_stale_readme_pin_is_rejected(tmp_path):
    # The case expect_literal misses: every other pin still names the current
    # version, so the version string is present and only a per-pin check fails.
    version = _readme_pin_version()
    pin = f"io.github.sanchitmonga22:runanywhere-sdk:{version}"
    result = _mutate_readme(tmp_path, pin, "io.github.sanchitmonga22:runanywhere-sdk:0.0.1")
    assert result.returncode == 1
    assert (
        f"expected {version}, found 'io.github.sanchitmonga22:runanywhere-sdk:0.0.1'"
        in result.stderr
    )


def test_readme_pin_with_a_prerelease_suffix_is_rejected(tmp_path):
    # The version must end the pin: a suffix names a different artifact.
    version = _readme_pin_version()
    result = _mutate_readme(tmp_path, f"runanywhere=={version}", f"runanywhere=={version}-rc.1")
    assert result.returncode == 1
    assert f"found 'runanywhere=={version}-rc.1'" in result.stderr


def test_readme_pin_with_an_attached_prerelease_suffix_is_rejected(tmp_path):
    # PEP 440 attaches the suffix with no separator; a prefix match would pass it.
    version = _readme_pin_version()
    result = _mutate_readme(tmp_path, f"runanywhere=={version}", f"runanywhere=={version}rc1")
    assert result.returncode == 1
    assert f"found 'runanywhere=={version}rc1'" in result.stderr


def test_readme_pin_with_an_unrecognized_suffix_is_rejected(tmp_path):
    # A suffix the version regex does not know must not be cut off before the
    # comparison, or the truncated pin reads as current.
    version = _readme_pin_version()
    for suffix in ("+build.1", "_rc1"):
        result = _mutate_readme(
            tmp_path / suffix.strip("+_"),
            f"runanywhere=={version}",
            f"runanywhere=={version}{suffix}",
        )
        assert result.returncode == 1
        assert f"found 'runanywhere=={version}{suffix}'" in result.stderr


def test_unpinned_package_beside_a_pinned_one_is_rejected(tmp_path):
    # @runanywhere/core is still pinned, so the shape has a match; the gate has
    # to look at every package reference, not only the version-shaped ones.
    version = _readme_pin_version()
    result = _mutate_readme(
        tmp_path, f"@runanywhere/llamacpp@{version}", "@runanywhere/llamacpp@latest"
    )
    assert result.returncode == 1
    assert "found '@runanywhere/llamacpp@latest'" in result.stderr


def test_readme_pin_followed_by_a_full_stop_passes(tmp_path):
    # Sentence punctuation after a pin is not part of the version; reading it as
    # a suffix fails the gate and makes the sync delete the full stop.
    version = _readme_pin_version()
    result = _mutate_readme(tmp_path, f"runanywhere=={version}", f"runanywhere=={version}.")
    assert result.returncode == 0, result.stderr


def test_readme_pin_shape_that_matches_nothing_is_rejected(tmp_path):
    # A shape with no match means the README was reworded under the gate, which
    # would otherwise stop checking that install command without saying so.
    version = _readme_pin_version()
    result = _mutate_readme(tmp_path, f"runanywhere=={version}", "runanywhere")
    assert result.returncode == 1
    assert "no version pin matches 'runanywhere=='" in result.stderr


def test_readme_temp_marker_for_another_release_is_rejected(tmp_path):
    # A marker left over from an earlier release must not keep vouching for the
    # old pins after the next bump.
    version = _core_version()
    result = _mutate_readme(
        tmp_path,
        f"until v{version} is on the package registries.",
        "until v0.0.1 is on the package registries.",
    )
    assert result.returncode == 1
    assert f"marker must name v{version}, found 'TEMP: install pins stay on" in result.stderr


def _readme_without_temp_marker(tmp_path, repin):
    sandbox = _mirror(tmp_path, writable={"README.md"})
    readme = sandbox / "README.md"
    lines = readme.read_text(encoding="utf-8").splitlines(keepends=True)
    text = "".join(line for line in lines if "TEMP: install pins stay on" not in line)
    if repin:
        # With the marker line gone, every remaining copy of the held version
        # is an install pin.
        text = text.replace(_readme_pin_version(), _core_version())
    readme.write_text(text, encoding="utf-8")
    return sandbox


def test_readme_pins_on_core_version_pass_without_a_temp_marker(tmp_path):
    # The state after publishing: marker deleted, pins synced to core/VERSION.
    result = _run(_readme_without_temp_marker(tmp_path, repin=True))
    assert result.returncode == 0, result.stderr


def test_deleting_only_the_temp_marker_rejects_stale_pins(tmp_path):
    # With the marker gone the pins must name core/VERSION again, so publishing
    # cannot be forgotten once the marker is deleted.
    pin_version = _readme_pin_version()
    if pin_version == _core_version():
        return  # no marker, so there are no held pins to go stale
    result = _run(_readme_without_temp_marker(tmp_path, repin=False))
    assert result.returncode == 1
    assert f"expected {_core_version()}, found 'runanywhere=={pin_version}'" in result.stderr


def _mutate_file(tmp_path, relative, old, new):
    sandbox = _mirror(tmp_path, writable={relative})
    path = sandbox / relative
    text = path.read_text(encoding="utf-8")
    assert text.count(old) >= 1, old
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    return _run(sandbox)


def test_stale_pip_extras_pin_in_the_python_readme_is_rejected(tmp_path):
    # runanywhere[extras]== is not one of the root README's shapes; the per-SDK
    # READMEs are the only place it appears.
    version = _core_version()
    result = _mutate_file(
        tmp_path,
        "bindings/python/README.md",
        f"runanywhere[rag]=={version}",
        "runanywhere[rag]==0.0.1",
    )
    assert result.returncode == 1
    assert (
        f"bindings/python/README.md: expected {version}, found 'runanywhere[rag]==0.0.1'"
        in result.stderr
    )


def test_stale_pin_in_a_kotlin_module_readme_is_rejected(tmp_path):
    version = _core_version()
    result = _mutate_file(
        tmp_path,
        "bindings/kotlin/modules/runanywhere-core-onnx/README.md",
        f"runanywhere-onnx:{version}",
        "runanywhere-onnx:0.0.1",
    )
    assert result.returncode == 1
    assert "runanywhere-core-onnx/README.md: expected" in result.stderr


def test_per_sdk_readme_with_no_pin_is_rejected(tmp_path):
    # A reworded README that no shape matches would silently drop out of the gate.
    result = _mutate_file(
        tmp_path,
        "bindings/web/packages/core/README.md",
        "npm install @runanywhere/web@",
        "npm install @runanywhere/web ",
    )
    assert result.returncode == 1
    assert "bindings/web/packages/core/README.md: no version pin matches" in result.stderr


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
