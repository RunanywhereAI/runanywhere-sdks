#!/usr/bin/env python3
"""
compile_model_for_qnn.py

Compile ONNX models for Qualcomm QNN NPU acceleration.

This script provides two compilation methods:
1. Qualcomm AI Hub (cloud-based, recommended) - requires free account
2. Local QNN SDK (requires manual QNN SDK installation)

Usage:
    # Using Qualcomm AI Hub (recommended)
    python compile_model_for_qnn.py model.onnx --method hub --device "Samsung Galaxy S24"
    
    # Using local QNN SDK
    python compile_model_for_qnn.py model.onnx --method local --qnn-sdk /path/to/qnn-sdk
    
    # Convert to FP16 first (recommended for NPU)
    python compile_model_for_qnn.py model.onnx --convert-fp16 --method hub

Requirements:
    pip install qai-hub onnx onnxruntime onnxconverter-common

Supported Target Devices (AI Hub):
    - "Samsung Galaxy S24"      - Snapdragon 8 Gen 3 (SM8650)
    - "Samsung Galaxy S23"      - Snapdragon 8 Gen 2 (SM8550)
    - "OnePlus 12"              - Snapdragon 8 Gen 3 (SM8650)
    - "Google Pixel 8 Pro"      - Google Tensor G3
    - "Xiaomi 14"               - Snapdragon 8 Gen 3 (SM8650)
"""

import argparse
import os
import sys
from pathlib import Path

def check_dependencies():
    """Check if required packages are installed."""
    missing = []
    
    try:
        import onnx
    except ImportError:
        missing.append("onnx")
    
    try:
        import onnxruntime
    except ImportError:
        missing.append("onnxruntime")
    
    if missing:
        print(f"Missing dependencies: {', '.join(missing)}")
        print(f"Install with: pip install {' '.join(missing)}")
        return False
    return True

def convert_to_fp16(model_path: str, output_path: str) -> str:
    """Convert ONNX model to FP16 for better NPU performance."""
    import onnx
    from onnxconverter_common import float16
    
    print(f"Converting {model_path} to FP16...")
    
    model = onnx.load(model_path)
    model_fp16 = float16.convert_float_to_float16(
        model,
        keep_io_types=True,  # Keep input/output as FP32 for compatibility
        disable_shape_infer=False
    )
    
    onnx.save(model_fp16, output_path)
    
    original_size = os.path.getsize(model_path) / (1024 * 1024)
    new_size = os.path.getsize(output_path) / (1024 * 1024)
    
    print(f"  Original size: {original_size:.1f} MB")
    print(f"  FP16 size:     {new_size:.1f} MB")
    print(f"  Reduction:     {(1 - new_size/original_size) * 100:.1f}%")
    
    return output_path

def compile_with_ai_hub(model_path: str, device_name: str, output_dir: str) -> str:
    """Compile ONNX model using Qualcomm AI Hub (cloud-based)."""
    try:
        import qai_hub as hub
    except ImportError:
        print("qai-hub not installed. Install with: pip install qai-hub")
        print("Then login with: qai-hub login")
        sys.exit(1)
    
    print(f"\n{'='*60}")
    print(f"Compiling for: {device_name}")
    print(f"Model: {model_path}")
    print(f"{'='*60}\n")
    
    # Submit compilation job
    print("Submitting compilation job to Qualcomm AI Hub...")
    compile_job = hub.submit_compile_job(
        model=model_path,
        device=hub.Device(device_name),
        options="--target_runtime qnn_context_binary",
    )
    
    print(f"Job ID: {compile_job.job_id}")
    print("Waiting for compilation (this may take several minutes)...")
    
    # Wait for completion
    compile_job.wait()
    
    status = compile_job.get_status()
    if status.success:
        # Download result
        target_model = compile_job.get_target_model()
        
        device_slug = device_name.replace(" ", "_").lower()
        model_name = Path(model_path).stem
        output_path = os.path.join(output_dir, f"{model_name}_qnn_{device_slug}.bin")
        
        target_model.download(output_path)
        
        print(f"\n✅ Compilation successful!")
        print(f"   Output: {output_path}")
        print(f"   Size: {os.path.getsize(output_path) / (1024*1024):.1f} MB")
        
        return output_path
    else:
        print(f"\n❌ Compilation failed: {status.message}")
        return None

def compile_with_local_sdk(model_path: str, qnn_sdk_root: str, output_dir: str, target_soc: str = "sm8650") -> str:
    """Compile ONNX model using local QNN SDK."""
    
    if not qnn_sdk_root or not os.path.isdir(qnn_sdk_root):
        print(f"QNN SDK not found at: {qnn_sdk_root}")
        print("Download from: https://qpm.qualcomm.com")
        sys.exit(1)
    
    converter = os.path.join(qnn_sdk_root, "bin", "x86_64-linux-clang", "qnn-onnx-converter")
    if not os.path.exists(converter):
        # Try Windows path
        converter = os.path.join(qnn_sdk_root, "bin", "x86_64-windows-msvc", "qnn-onnx-converter.exe")
    
    if not os.path.exists(converter):
        print(f"qnn-onnx-converter not found in {qnn_sdk_root}")
        print("Make sure QNN SDK is properly installed")
        sys.exit(1)
    
    model_name = Path(model_path).stem
    cpp_output = os.path.join(output_dir, f"{model_name}.cpp")
    bin_output = os.path.join(output_dir, f"{model_name}_qnn.bin")
    
    print(f"\n{'='*60}")
    print(f"Compiling with local QNN SDK")
    print(f"Model: {model_path}")
    print(f"Target SoC: {target_soc}")
    print(f"{'='*60}\n")
    
    # Step 1: Convert ONNX to QNN
    print("Step 1: Converting ONNX to QNN format...")
    import subprocess
    
    cmd = [
        converter,
        "--input_network", model_path,
        "--output_path", cpp_output,
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Conversion failed: {result.stderr}")
        return None
    
    print(f"  Generated: {cpp_output}")
    
    # Step 2: Generate model library
    lib_generator = os.path.join(qnn_sdk_root, "bin", "x86_64-linux-clang", "qnn-model-lib-generator")
    if os.path.exists(lib_generator):
        print("Step 2: Generating model library...")
        cmd = [
            lib_generator,
            "-c", cpp_output,
            "-b", bin_output,
            "-t", "aarch64-android"
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            print(f"  Generated: {bin_output}")
        else:
            print(f"  Warning: Library generation failed: {result.stderr}")
    
    print(f"\n✅ Local compilation complete!")
    print(f"   Output directory: {output_dir}")
    
    return cpp_output

def main():
    parser = argparse.ArgumentParser(
        description="Compile ONNX models for Qualcomm QNN NPU acceleration",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Compile for Galaxy S24 using AI Hub
    python compile_model_for_qnn.py kokoro.onnx --method hub --device "Samsung Galaxy S24"
    
    # Convert to FP16 first (recommended)
    python compile_model_for_qnn.py kokoro.onnx --convert-fp16 --method hub
    
    # Use local QNN SDK
    python compile_model_for_qnn.py kokoro.onnx --method local --qnn-sdk ~/qnn-sdk

Supported Devices:
    Samsung Galaxy S24, S23, S22, S21
    OnePlus 12, 11, 10, 9
    Xiaomi 14, 13, 12
    Google Pixel 8 Pro, 7 Pro
    Any Snapdragon 8 Gen 1/2/3 device
        """
    )
    
    parser.add_argument("model", help="Path to ONNX model file")
    parser.add_argument("--method", choices=["hub", "local"], default="hub",
                        help="Compilation method (default: hub)")
    parser.add_argument("--device", default="Samsung Galaxy S24",
                        help="Target device for AI Hub compilation")
    parser.add_argument("--qnn-sdk", help="Path to local QNN SDK")
    parser.add_argument("--target-soc", default="sm8650",
                        help="Target SoC for local compilation (default: sm8650)")
    parser.add_argument("--output-dir", default="./qnn_output",
                        help="Output directory for compiled models")
    parser.add_argument("--convert-fp16", action="store_true",
                        help="Convert model to FP16 before compilation")
    parser.add_argument("--list-devices", action="store_true",
                        help="List supported devices for AI Hub")
    
    args = parser.parse_args()
    
    if args.list_devices:
        print("Supported devices for Qualcomm AI Hub:")
        print("")
        devices = [
            ("Samsung Galaxy S24", "Snapdragon 8 Gen 3 (SM8650)", "V75"),
            ("Samsung Galaxy S23", "Snapdragon 8 Gen 2 (SM8550)", "V73"),
            ("Samsung Galaxy S22", "Snapdragon 8 Gen 1 (SM8450)", "V69"),
            ("OnePlus 12", "Snapdragon 8 Gen 3 (SM8650)", "V75"),
            ("OnePlus 11", "Snapdragon 8 Gen 2 (SM8550)", "V73"),
            ("Xiaomi 14", "Snapdragon 8 Gen 3 (SM8650)", "V75"),
            ("Google Pixel 8 Pro", "Google Tensor G3", "Custom"),
        ]
        print(f"{'Device':<25} {'SoC':<30} {'HTP':<10}")
        print("-" * 65)
        for device, soc, htp in devices:
            print(f"{device:<25} {soc:<30} {htp:<10}")
        return
    
    if not check_dependencies():
        sys.exit(1)
    
    if not os.path.exists(args.model):
        print(f"Model not found: {args.model}")
        sys.exit(1)
    
    os.makedirs(args.output_dir, exist_ok=True)
    
    model_path = args.model
    
    # Convert to FP16 if requested
    if args.convert_fp16:
        try:
            from onnxconverter_common import float16
            fp16_path = os.path.join(args.output_dir, Path(args.model).stem + "_fp16.onnx")
            model_path = convert_to_fp16(args.model, fp16_path)
        except ImportError:
            print("onnxconverter-common not installed. Install with:")
            print("  pip install onnxconverter-common")
            sys.exit(1)
    
    # Compile model
    if args.method == "hub":
        output = compile_with_ai_hub(model_path, args.device, args.output_dir)
    else:
        qnn_sdk = args.qnn_sdk or os.environ.get("QNN_SDK_ROOT")
        output = compile_with_local_sdk(model_path, qnn_sdk, args.output_dir, args.target_soc)
    
    if output:
        print(f"\n{'='*60}")
        print("Next steps:")
        print("1. Copy the compiled model to your Android app")
        print("2. Use with QNN execution provider in ONNX Runtime")
        print("3. Or load as pre-compiled context binary")
        print(f"{'='*60}")
    else:
        print("\nCompilation failed. Check the errors above.")
        sys.exit(1)

if __name__ == "__main__":
    main()
