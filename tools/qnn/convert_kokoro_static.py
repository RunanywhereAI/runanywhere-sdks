#!/usr/bin/env python3
"""
Convert Kokoro TTS ONNX model to fully static shapes for QNN HTP (NPU).

QNN HTP requires all input AND output shapes to be fixed at compile time.
This script modifies the Kokoro model to:
1. Fix input sequence length (e.g., 50 or 512 tokens)
2. Fix output audio length by padding to maximum (e.g., 192,000 samples = 8s)

Usage:
    python convert_kokoro_static.py \
        --input /path/to/kokoro.onnx \
        --output /path/to/kokoro_static.onnx \
        --seq_length 512 \
        --max_audio_samples 192000

Requirements:
    pip install onnx onnxruntime numpy

Author: RunAnywhere AI Team
"""

import argparse
import numpy as np
import onnx
from onnx import helper, numpy_helper, TensorProto
from pathlib import Path


def analyze_model(model_path: str) -> dict:
    """Analyze ONNX model structure."""
    print(f"\n=== Analyzing {model_path} ===\n")
    model = onnx.load(model_path)

    info = {
        "inputs": {},
        "outputs": {},
        "opset": [op.version for op in model.opset_import],
        "ir_version": model.ir_version,
    }

    type_map = {
        TensorProto.FLOAT: "FLOAT",
        TensorProto.INT32: "INT32",
        TensorProto.INT64: "INT64",
        TensorProto.BOOL: "BOOL",
        TensorProto.FLOAT16: "FLOAT16",
    }

    print("Inputs:")
    for inp in model.graph.input:
        shape = []
        for d in inp.type.tensor_type.shape.dim:
            if d.dim_value:
                shape.append(d.dim_value)
            elif d.dim_param:
                shape.append(d.dim_param)  # Named dimension
            else:
                shape.append(-1)  # Unknown/dynamic

        dtype = type_map.get(inp.type.tensor_type.elem_type,
                            str(inp.type.tensor_type.elem_type))
        info["inputs"][inp.name] = {"shape": shape, "dtype": dtype}
        print(f"  {inp.name}: {dtype} {shape}")

    print("\nOutputs:")
    for out in model.graph.output:
        shape = []
        for d in out.type.tensor_type.shape.dim:
            if d.dim_value:
                shape.append(d.dim_value)
            elif d.dim_param:
                shape.append(d.dim_param)
            else:
                shape.append(-1)

        dtype = type_map.get(out.type.tensor_type.elem_type,
                            str(out.type.tensor_type.elem_type))
        info["outputs"][out.name] = {"shape": shape, "dtype": dtype}
        print(f"  {out.name}: {dtype} {shape}")

    print(f"\nOpset: {info['opset']}")
    return info


def fix_input_shapes(model: onnx.ModelProto, seq_length: int) -> onnx.ModelProto:
    """Fix input sequence length to a specific value."""
    print(f"\n=== Fixing input shapes (seq_length={seq_length}) ===\n")

    for inp in model.graph.input:
        # Find the token input (could be 'input_ids' or 'tokens')
        if inp.name in ["input_ids", "tokens"]:
            # Clear existing dimensions
            while len(inp.type.tensor_type.shape.dim) > 0:
                inp.type.tensor_type.shape.dim.pop()

            # Add fixed dimensions [1, seq_length]
            dim1 = inp.type.tensor_type.shape.dim.add()
            dim1.dim_value = 1
            dim2 = inp.type.tensor_type.shape.dim.add()
            dim2.dim_value = seq_length

            print(f"  Fixed {inp.name} to shape [1, {seq_length}]")

    return model


def fix_output_shapes(model: onnx.ModelProto, max_audio_samples: int) -> onnx.ModelProto:
    """
    Fix output audio length to a specific maximum value.

    This is more complex because we need to modify the graph to pad the output.
    For now, we just fix the shape declaration - actual padding would need
    to be added via graph modification.
    """
    print(f"\n=== Fixing output shapes (max_audio={max_audio_samples}) ===\n")

    for out in model.graph.output:
        if out.name in ["audio", "waveform"]:
            # Clear existing dimensions
            while len(out.type.tensor_type.shape.dim) > 0:
                out.type.tensor_type.shape.dim.pop()

            # Add fixed dimension [max_audio_samples]
            dim = out.type.tensor_type.shape.dim.add()
            dim.dim_value = max_audio_samples

            print(f"  Fixed {out.name} to shape [{max_audio_samples}]")
            print(f"    Note: This only fixes the declaration. The model may still")
            print(f"    output variable-length data unless graph is modified.")

    return model


def add_output_padding(model: onnx.ModelProto, max_audio_samples: int) -> onnx.ModelProto:
    """
    Add padding operation to ensure output is always max_audio_samples long.

    This modifies the graph to:
    1. Get actual output length
    2. Pad with zeros to max_audio_samples
    3. Return padded output

    This is a more invasive change but ensures true static output.
    """
    print(f"\n=== Adding output padding ===\n")

    # Find the output tensor name
    output_names = [out.name for out in model.graph.output if out.name in ["audio", "waveform"]]
    if not output_names:
        print("  Warning: No audio output found, skipping padding")
        return model

    original_output = output_names[0]

    # Find the node that produces this output
    producer_node = None
    for node in model.graph.node:
        if original_output in node.output:
            producer_node = node
            break

    if not producer_node:
        print(f"  Warning: Could not find producer of {original_output}")
        return model

    print(f"  Original output: {original_output}")
    print(f"  Producer node: {producer_node.op_type}")

    # Create intermediate output name
    intermediate_output = f"{original_output}_unpadded"

    # Update producer node to output to intermediate
    for i, out in enumerate(producer_node.output):
        if out == original_output:
            producer_node.output[i] = intermediate_output

    # Create Pad node
    # pad_values format: [before_0, before_1, ..., after_0, after_1, ...]
    # For 1D output, we pad at the end: [0, max_audio_samples - dynamic_length]

    # Since we can't compute dynamic padding in static graph, we use a simpler approach:
    # Use Concat to append zeros, then Slice to fixed length

    # Create zeros constant for padding
    zeros = numpy_helper.from_array(
        np.zeros(max_audio_samples, dtype=np.float32),
        name="padding_zeros"
    )
    model.graph.initializer.append(zeros)

    # Concat original output with zeros
    concat_output = f"{original_output}_concat"
    concat_node = helper.make_node(
        "Concat",
        inputs=[intermediate_output, "padding_zeros"],
        outputs=[concat_output],
        axis=0  # Concatenate along first (only) axis
    )
    model.graph.node.append(concat_node)

    # Slice to exact length
    starts = numpy_helper.from_array(np.array([0], dtype=np.int64), name="slice_starts")
    ends = numpy_helper.from_array(np.array([max_audio_samples], dtype=np.int64), name="slice_ends")
    axes = numpy_helper.from_array(np.array([0], dtype=np.int64), name="slice_axes")
    model.graph.initializer.extend([starts, ends, axes])

    slice_node = helper.make_node(
        "Slice",
        inputs=[concat_output, "slice_starts", "slice_ends", "slice_axes"],
        outputs=[original_output]
    )
    model.graph.node.append(slice_node)

    # Update output shape
    for out in model.graph.output:
        if out.name == original_output:
            while len(out.type.tensor_type.shape.dim) > 0:
                out.type.tensor_type.shape.dim.pop()
            dim = out.type.tensor_type.shape.dim.add()
            dim.dim_value = max_audio_samples

    print(f"  Added padding: {intermediate_output} -> concat -> slice -> {original_output}")
    print(f"  Output shape: [{max_audio_samples}]")

    return model


def validate_model(model: onnx.ModelProto) -> bool:
    """Validate the modified model."""
    print("\n=== Validating model ===\n")
    try:
        onnx.checker.check_model(model)
        print("  Model is valid!")
        return True
    except Exception as e:
        print(f"  Validation error: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Convert Kokoro ONNX model to fully static shapes for QNN HTP"
    )
    parser.add_argument(
        "--input", "-i",
        required=True,
        help="Input ONNX model path"
    )
    parser.add_argument(
        "--output", "-o",
        required=False,
        help="Output ONNX model path (required unless --analyze_only)"
    )
    parser.add_argument(
        "--seq_length", "-s",
        type=int,
        default=512,
        help="Fixed input sequence length (default: 512)"
    )
    parser.add_argument(
        "--max_audio_samples", "-a",
        type=int,
        default=192000,
        help="Maximum audio output samples (default: 192000 = 8s at 24kHz)"
    )
    parser.add_argument(
        "--add_padding",
        action="store_true",
        help="Add padding operation to graph (more invasive but ensures static output)"
    )
    parser.add_argument(
        "--analyze_only",
        action="store_true",
        help="Only analyze the model, don't modify"
    )

    args = parser.parse_args()

    # Analyze original model
    info = analyze_model(args.input)

    if args.analyze_only:
        return

    # Validate output path
    if not args.output:
        print("Error: --output is required unless --analyze_only is set")
        return 1

    # Load model
    print(f"\nLoading model from {args.input}...")
    model = onnx.load(args.input)

    # Fix input shapes
    model = fix_input_shapes(model, args.seq_length)

    # Fix output shapes
    if args.add_padding:
        model = add_output_padding(model, args.max_audio_samples)
    else:
        model = fix_output_shapes(model, args.max_audio_samples)

    # Validate
    if validate_model(model):
        # Save
        print(f"\nSaving model to {args.output}...")
        onnx.save(model, args.output)
        print("Done!")

        # Analyze output
        analyze_model(args.output)
    else:
        print("\nModel validation failed. Not saving.")
        return 1

    print("\n" + "="*60)
    print("NEXT STEPS for full NPU support:")
    print("="*60)
    print("""
1. Generate QNN context binary (requires Linux):

   # On Linux machine with QAIRT SDK:
   export QNN_SDK_ROOT=/path/to/qairt/2.40.0.251030

   python3 -c "
   import onnxruntime as ort
   options = ort.SessionOptions()
   options.add_session_config_entry('ep.context_enable', '1')
   options.add_session_config_entry('ep.context_file_path', './kokoro_ctx.onnx')
   options.add_session_config_entry('ep.context_embed_mode', '0')

   session = ort.InferenceSession(
       'kokoro_static.onnx',
       sess_options=options,
       providers=[('QNNExecutionProvider', {
           'backend_path': 'libQnnHtp.so',
           'htp_performance_mode': 'burst'
       })]
   )
   print('Context binary generated!')
   "

2. Deploy to device:
   - Copy kokoro_ctx.onnx and .bin files to device
   - Update KokoroQnnTTS to load context model

3. For truly static output, re-export from PyTorch with padding built-in.
""")


if __name__ == "__main__":
    main()
