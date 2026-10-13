#!/usr/bin/env python3
"""Run the model-free cancellation/usage regression against built MLX dependencies.

Build a Swift consumer with Xcode first, then pass its existing build locations:
  python3 bindings/swift/scripts/test-mlx-cancellation.py \\
    --products-dir /path/to/DerivedData/Build/Products/Release \\
    --checkouts-dir /path/to/DerivedData/SourcePackages/checkouts

This compiles only the test executable. It never downloads or builds a model.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--products-dir", type=Path, required=True)
parser.add_argument("--checkouts-dir", type=Path, required=True)
args = parser.parse_args()
products = args.products_dir.resolve()
checkouts = args.checkouts_dir.resolve()
swift_root = Path(__file__).resolve().parents[1]
modules = ["MLXLMCommon", "MLX", "MLXNN", "MLXFast", "MLXOptimizers", "Cmlx",
           "ComplexModule", "RealModule", "Numerics", "_NumericsShims"]
objects = [products / (name + ".o") for name in modules]
missing = [str(path) for path in objects if not path.is_file()]
if missing:
    parser.error("Build MLX dependencies first; missing: " + ", ".join(missing))
with tempfile.TemporaryDirectory(prefix="mlx-cancellation-") as directory:
    work = Path(directory)
    command = ["swiftc", "-parse-as-library", "-I", str(products),
               "-I", str(checkouts / "mlx-swift/Source/Cmlx/include"),
               "-I", str(checkouts / "swift-numerics/Sources/_NumericsShims/include"),
               "-Xlinker", "-dead_strip",
               str(swift_root / "Tests/MLXRuntimeStandalone/MLXCancellationUsageTests.swift"),
               str(swift_root / "Sources/MLXRuntime/MLXTextStopFilter.swift"),
               *map(str, objects), "-o", str(work / "check"), "-lc++"]
    for framework in ["Accelerate", "Metal", "Foundation", "CoreImage", "CoreGraphics"]:
        command += ["-framework", framework]
    subprocess.run(command, check=True)
    metallibs = list(products.glob("**/default.metallib"))
    if metallibs:
        (work / "mlx.metallib").symlink_to(metallibs[0])
    subprocess.run([str(work / "check")], check=True)
