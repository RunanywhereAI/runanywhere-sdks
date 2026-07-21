#!/usr/bin/env python3
"""Export the pinned NVIDIA BigVGAN 22 kHz checkpoint as a provenance-safe ONNX bundle.

This tool deliberately does not download or publish anything. The caller supplies an
exact local copy of the official Hugging Face model files and a clean checkout of the
official NVIDIA/BigVGAN source revision. Both are verified before PyTorch deserializes
the checkpoint. The output records source revisions, hashes, exporter versions, ONNX
metadata, all upstream license notices, a full ONNX checker result, and numerical
parity over fixed and dynamic input shapes.

The resulting bundle is suitable for local RunAnywhere provider validation. Adding it
to a downloadable catalog still requires an authorized, immutable hosted location.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import gc
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any


MODEL_REPOSITORY = "nvidia/bigvgan_v2_22khz_80band_256x"
MODEL_REVISION = "633ff708ed5b74903e86ff1298cf4a98e921c513"
CODE_REPOSITORY = "NVIDIA/BigVGAN"
CODE_REVISION = "7d2b454564a6c7d014227f635b7423881f14bdac"
EXPECTED_TORCH_VERSION = "2.10.0"
EXPECTED_ONNX_VERSION = "1.20.1"
EXPECTED_ORT_VERSION = "1.24.2"


@dataclass(frozen=True)
class SourceFile:
    filename: str
    size_bytes: int
    sha256: str


MODEL_FILES = (
    SourceFile(
        "bigvgan_generator.pt",
        449_228_171,
        "e95ba25972d3de0628d99cd156e9315a9c018899bf739988959ebe3544080ced",
    ),
    SourceFile(
        "config.json",
        1_405,
        "88a1f47acf747db0b21e97a389d838566147f7a5464583ff5c8d819d870f03ee",
    ),
    SourceFile(
        "LICENSE",
        1_076,
        "90459cd52fc41bd723df7c0c76fac1e4dd60e6bfd644a7e2a93f325bed4f6d95",
    ),
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _verify_file(root: Path, expected: SourceFile) -> None:
    path = root / expected.filename
    if not path.is_file():
        raise ValueError(f"missing pinned source file: {path}")
    actual_size = path.stat().st_size
    if actual_size != expected.size_bytes:
        raise ValueError(
            f"source size mismatch for {expected.filename}: "
            f"expected {expected.size_bytes}, got {actual_size}"
        )
    actual_sha = _sha256(path)
    if actual_sha != expected.sha256:
        raise ValueError(
            f"source SHA-256 mismatch for {expected.filename}: "
            f"expected {expected.sha256}, got {actual_sha}"
        )


def verify_model_sources(model_dir: Path) -> None:
    for source in MODEL_FILES:
        _verify_file(model_dir, source)


def _run_git(code_dir: Path, *args: str) -> str:
    git = shutil.which("git")
    if not git:
        raise ValueError("git is required to verify the official BigVGAN source checkout")
    completed = subprocess.run(
        [git, "-C", str(code_dir), *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise ValueError(f"cannot verify BigVGAN source checkout: {detail}")
    return completed.stdout.strip()


def verify_code_checkout(code_dir: Path) -> None:
    if _run_git(code_dir, "rev-parse", "HEAD") != CODE_REVISION:
        raise ValueError(f"BigVGAN source checkout must be exactly {CODE_REVISION}")
    if _run_git(code_dir, "status", "--porcelain", "--untracked-files=no"):
        raise ValueError("BigVGAN source checkout has modified tracked files")
    required = [
        code_dir / "bigvgan.py",
        code_dir / "env.py",
        code_dir / "LICENSE",
        code_dir / "incl_licenses",
    ]
    if any(not path.exists() for path in required):
        raise ValueError("BigVGAN source checkout is missing code or license notices")


def _metrics(numpy: Any, reference: Any, candidate: Any) -> dict[str, object]:
    diff = candidate.astype(numpy.float64) - reference.astype(numpy.float64)
    ref = reference.astype(numpy.float64).reshape(-1)
    out = candidate.astype(numpy.float64).reshape(-1)
    return {
        "reference_shape": list(reference.shape),
        "candidate_shape": list(candidate.shape),
        "max_abs": float(numpy.max(numpy.abs(diff))),
        "mean_abs": float(numpy.mean(numpy.abs(diff))),
        "rmse": float(numpy.sqrt(numpy.mean(diff * diff))),
        "correlation": float(numpy.corrcoef(ref, out)[0, 1]),
        "allclose_rtol_atol_1e-4": bool(
            numpy.allclose(candidate, reference, rtol=1e-4, atol=1e-4)
        ),
    }


def export_bundle(
    model_dir: Path,
    code_dir: Path,
    output_dir: Path,
    threads: int = 2,
) -> dict[str, object]:
    model_dir = model_dir.resolve()
    code_dir = code_dir.resolve()
    output_dir = output_dir.resolve()
    if threads not in (1, 2):
        raise ValueError("--threads must be 1 or 2")
    verify_model_sources(model_dir)
    verify_code_checkout(code_dir)
    if output_dir.exists():
        raise ValueError(f"refusing to overwrite existing output: {output_dir}")

    partial_dir = output_dir.with_name(f".{output_dir.name}.partial-{os.getpid()}")
    if partial_dir.exists():
        raise ValueError(f"refusing to reuse partial output: {partial_dir}")

    # The official repository uses top-level imports. Add only after the exact clean
    # source revision is proven, and import heavyweight exporter dependencies lazily so
    # source-verification unit tests do not require PyTorch.
    sys.path.insert(0, str(code_dir))
    try:
        import numpy
        import onnx
        import onnxruntime as ort
        import torch
        import torch.nn.functional as torch_functional
        from alias_free_activation.torch.act import Activation1d
        from alias_free_activation.torch.filter import LowPassFilter1d
        from alias_free_activation.torch.resample import UpSample1d
        from bigvgan import BigVGAN
        from env import AttrDict
    except ImportError as error:
        raise ValueError(f"missing BigVGAN export dependency: {error}") from error

    versions = {
        "python": sys.version.split()[0],
        "torch": torch.__version__,
        "numpy": numpy.__version__,
        "onnx": onnx.__version__,
        "onnxruntime": ort.__version__,
    }
    expected_versions = {
        "torch": EXPECTED_TORCH_VERSION,
        "onnx": EXPECTED_ONNX_VERSION,
        "onnxruntime": EXPECTED_ORT_VERSION,
    }
    mismatches = {
        name: (expected, versions[name])
        for name, expected in expected_versions.items()
        if versions[name] != expected
    }
    if mismatches:
        raise ValueError(f"exporter version mismatch: {mismatches}")

    def export_upsample_forward(self: Any, values: Any) -> Any:
        values = torch_functional.pad(values, (self.pad, self.pad), mode="replicate")
        values = self.ratio * torch_functional.conv_transpose1d(
            values,
            self.filter.expand(self.export_channels, -1, -1),
            stride=self.stride,
            groups=self.export_channels,
        )
        return values[..., self.pad_left : -self.pad_right]

    def export_lowpass_forward(self: Any, values: Any) -> Any:
        if self.padding:
            values = torch_functional.pad(
                values, (self.pad_left, self.pad_right), mode=self.padding_mode
            )
        return torch_functional.conv1d(
            values,
            self.filter.expand(self.export_channels, -1, -1),
            stride=self.stride,
            groups=self.export_channels,
        )

    def make_channel_groups_static(model: Any) -> None:
        # Legacy ONNX shape inference otherwise treats activation channel groups as
        # dynamic and rejects the depthwise resampling convolution. The group count is
        # architecturally fixed by each SnakeBeta parameter vector; only B and T remain
        # dynamic. This substitution is mathematically identical and parity-gated below.
        for module in model.modules():
            if not isinstance(module, Activation1d):
                continue
            channels = int(module.act.alpha.numel())
            module.upsample.export_channels = channels
            module.upsample.forward = export_upsample_forward.__get__(
                module.upsample, UpSample1d
            )
            module.downsample.lowpass.export_channels = channels
            module.downsample.lowpass.forward = export_lowpass_forward.__get__(
                module.downsample.lowpass, LowPassFilter1d
            )

    torch.set_num_threads(threads)
    torch.set_num_interop_threads(1)
    torch.manual_seed(1234)
    with (model_dir / "config.json").open(encoding="utf-8") as stream:
        hparams = AttrDict(json.load(stream))
    model = BigVGAN(hparams, use_cuda_kernel=False)
    # weights_only is intentionally explicit. The official checkpoint contains the
    # generator state dictionary; source hash validation occurs before deserialization.
    checkpoint = torch.load(
        model_dir / "bigvgan_generator.pt", map_location="cpu", weights_only=True
    )
    model.load_state_dict(checkpoint["generator"])
    del checkpoint
    gc.collect()
    model.remove_weight_norm()
    model.eval()
    make_channel_groups_static(model)

    try:
        partial_dir.mkdir(parents=True)
        inline_path = partial_dir / "model-inline.onnx"
        dummy = torch.zeros((1, 80, 8), dtype=torch.float32)
        with torch.inference_mode():
            torch.onnx.export(
                model,
                (dummy,),
                inline_path,
                input_names=["mel_spectrogram"],
                output_names=["audio_waveform"],
                dynamic_axes={
                    "mel_spectrogram": {0: "batch", 2: "time_frames"},
                    "audio_waveform": {0: "batch", 2: "256*time_frames"},
                },
                opset_version=18,
                do_constant_folding=True,
                dynamo=False,
                external_data=False,
            )

        graph = onnx.load(str(inline_path), load_external_data=True)
        graph.producer_name = "RunAnywhere pinned NVIDIA BigVGAN export via PyTorch"
        graph.doc_string = (
            f"Source {MODEL_REPOSITORY}@{MODEL_REVISION}; "
            f"code {CODE_REPOSITORY}@{CODE_REVISION}"
        )
        metadata = {
            "runanywhere.source_model": f"{MODEL_REPOSITORY}@{MODEL_REVISION}",
            "runanywhere.source_code": f"{CODE_REPOSITORY}@{CODE_REVISION}",
            "runanywhere.checkpoint_sha256": MODEL_FILES[0].sha256,
            "runanywhere.config_sha256": MODEL_FILES[1].sha256,
            "runanywhere.torch_version": torch.__version__,
            "runanywhere.onnx_version": onnx.__version__,
        }
        for key, value in metadata.items():
            prop = graph.metadata_props.add()
            prop.key = key
            prop.value = value

        model_path = partial_dir / "model.onnx"
        data_path = partial_dir / "model.onnx.data"
        onnx.save_model(
            graph,
            str(model_path),
            save_as_external_data=True,
            all_tensors_to_one_file=True,
            location=data_path.name,
            size_threshold=1024,
            convert_attribute=False,
        )
        inline_path.unlink()
        del graph
        gc.collect()

        shutil.copy2(model_dir / "config.json", partial_dir / "config.json")
        shutil.copy2(model_dir / "LICENSE", partial_dir / "LICENSE")
        shutil.copy2(Path(__file__), partial_dir / Path(__file__).name)
        shutil.copytree(code_dir / "incl_licenses", partial_dir / "incl_licenses")

        onnx.checker.check_model(str(model_path), full_check=True)
        options = ort.SessionOptions()
        options.intra_op_num_threads = threads
        options.inter_op_num_threads = 1
        session = ort.InferenceSession(
            str(model_path), sess_options=options, providers=["CPUExecutionProvider"]
        )

        generator = numpy.random.default_rng(20260721)
        cases = {
            "zeros_t1": numpy.zeros((1, 80, 1), dtype=numpy.float32),
            "ramp_t3": numpy.linspace(
                -2.0, 1.0, 1 * 80 * 3, dtype=numpy.float32
            ).reshape(1, 80, 3),
            "random_t8": generator.normal(0.0, 0.7, (1, 80, 8)).astype(numpy.float32),
            "random_t17": generator.normal(0.0, 0.7, (1, 80, 17)).astype(numpy.float32),
            "batch2_t5": generator.normal(0.0, 0.7, (2, 80, 5)).astype(numpy.float32),
        }
        sweep: dict[str, dict[str, object]] = {}
        for name, mel in cases.items():
            with torch.inference_mode():
                reference = model(torch.from_numpy(mel)).numpy()
            candidate = session.run(["audio_waveform"], {"mel_spectrogram": mel})[0]
            result = _metrics(numpy, reference, candidate)
            expected_shape = [mel.shape[0], 1, mel.shape[2] * 256]
            result["expected_shape"] = expected_shape
            result["shape_exact"] = list(candidate.shape) == expected_shape
            if not result["shape_exact"] or not result["allclose_rtol_atol_1e-4"]:
                raise ValueError(f"ONNX parity failed for {name}: {result}")
            sweep[name] = result

        artifact_paths = sorted(
            path
            for path in partial_dir.rglob("*")
            if path.is_file() and path.name != "runanywhere-export-manifest.json"
        )
        manifest: dict[str, object] = {
            "schema": "runanywhere-bigvgan-onnx-bundle/v1",
            "source_model": {
                "repository": MODEL_REPOSITORY,
                "revision": MODEL_REVISION,
                "files": [
                    {
                        "filename": source.filename,
                        "url": (
                            f"https://huggingface.co/{MODEL_REPOSITORY}/resolve/"
                            f"{MODEL_REVISION}/{source.filename}"
                        ),
                        "size_bytes": source.size_bytes,
                        "sha256": source.sha256,
                    }
                    for source in MODEL_FILES
                ],
            },
            "source_code": {
                "repository": CODE_REPOSITORY,
                "revision": CODE_REVISION,
                "url": f"https://github.com/{CODE_REPOSITORY}/tree/{CODE_REVISION}",
            },
            "versions": versions,
            "contract": {
                "input": {
                    "name": "mel_spectrogram",
                    "dtype": "float32",
                    "shape": ["B", 80, "T"],
                },
                "output": {
                    "name": "audio_waveform",
                    "dtype": "float32",
                    "shape": ["B", 1, "256*T"],
                },
                "sample_rate_hz": 22_050,
                "hop_length": 256,
            },
            "artifacts": {
                str(path.relative_to(partial_dir)): {
                    "size_bytes": path.stat().st_size,
                    "sha256": _sha256(path),
                }
                for path in artifact_paths
            },
            "onnx_checker_full": "PASS",
            "dynamic_shape_parity": sweep,
        }
        (partial_dir / "runanywhere-export-manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        os.replace(partial_dir, output_dir)
        return manifest
    except BaseException:
        if partial_dir.exists():
            shutil.rmtree(partial_dir)
        raise


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--model-dir",
        required=True,
        type=Path,
        help="Directory containing the exact pinned official checkpoint/config/license",
    )
    parser.add_argument(
        "--code-dir",
        required=True,
        type=Path,
        help="Clean NVIDIA/BigVGAN checkout at the pinned source revision",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        type=Path,
        help="New path that will receive the verified ONNX bundle",
    )
    parser.add_argument("--threads", type=int, choices=(1, 2), default=2)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        manifest = export_bundle(args.model_dir, args.code_dir, args.output_dir, args.threads)
    except (OSError, RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    artifacts = manifest["artifacts"]
    assert isinstance(artifacts, dict)
    model = artifacts["model.onnx"]
    data = artifacts["model.onnx.data"]
    print(
        "Prepared pinned BigVGAN ONNX bundle: "
        f"model={model['sha256']} external_data={data['sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
