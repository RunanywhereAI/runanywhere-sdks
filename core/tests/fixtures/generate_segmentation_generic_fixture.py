#!/usr/bin/env python3
"""Generate a generic (non-SegFormer-default) semantic-segmentation ONNX fixture.

Emits model.onnx + config.json + preprocessor_config.json into the directory named
by argv[1]. The graph mirrors the committed segformer_tiny fixture
(AveragePool -> ReduceMean -> Tile -> Add(class_bias)) but is chosen so EVERY
observable value differs from the provider's file-local defaults, so the
end-to-end test can prove the provider reads them from the bundle:

  * input pixel_values[1,3,256,256]   (256 != the provider's kDefaultInputSize 512)
  * output logits[1,4,64,64]          (4 != SegFormer's 150; 64 != 128)
  * class_bias puts a +10 spike on channel 2 -> argmax is class 2 at every pixel
  * id2label = {0:background, 1:road, 2:person, 3:sky} -> winning label 'person'

Run by the CMake build (custom command) for test_segmentation_generic; also
usable by hand:  python3 generate_segmentation_generic_fixture.py <out_dir>
"""
import json
import os
import sys

import numpy as np
import onnx
from onnx import TensorProto, helper, numpy_helper

INPUT_SIZE = 256      # != provider kDefaultInputSize (512)
NUM_CLASSES = 4       # != SegFormer 150
POOL = 4              # AveragePool kernel/stride -> logits plane = 256 / 4 = 64 (!= 128)
WINNING_CLASS = 2     # argmax channel at every pixel


def build_model():
    plane = INPUT_SIZE // POOL
    pixel_values = helper.make_tensor_value_info(
        "pixel_values", TensorProto.FLOAT, [1, 3, INPUT_SIZE, INPUT_SIZE])
    logits = helper.make_tensor_value_info(
        "logits", TensorProto.FLOAT, [1, NUM_CLASSES, plane, plane])

    avgpool = helper.make_node(
        "AveragePool", ["pixel_values"], ["pooled"],
        kernel_shape=[POOL, POOL], strides=[POOL, POOL])
    reducemean = helper.make_node(
        "ReduceMean", ["pooled"], ["mean"], axes=[1], keepdims=1)
    repeats = numpy_helper.from_array(
        np.array([1, NUM_CLASSES, 1, 1], dtype=np.int64), name="repeats")
    tile = helper.make_node("Tile", ["mean", "repeats"], ["tiled"])
    bias = np.zeros((1, NUM_CLASSES, 1, 1), dtype=np.float32)
    bias[0, WINNING_CLASS, 0, 0] = 10.0  # channel 2 dominates every pixel
    class_bias = numpy_helper.from_array(bias, name="class_bias")
    add = helper.make_node("Add", ["tiled", "class_bias"], ["logits"])

    graph = helper.make_graph(
        [avgpool, reducemean, tile, add], "generic_segmentation",
        [pixel_values], [logits], [repeats, class_bias])
    model = helper.make_model(
        graph, producer_name="runanywhere-native-tests",
        opset_imports=[helper.make_opsetid("", 17)])
    model.ir_version = 9
    onnx.checker.check_model(model)
    return model


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: generate_segmentation_generic_fixture.py <out_dir>")
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)

    onnx.save(build_model(), os.path.join(out_dir, "model.onnx"))

    config = {
        "architectures": ["SegformerForSemanticSegmentation"],
        "id2label": {"0": "background", "1": "road", "2": "person", "3": "sky"},
        "model_type": "segformer",
        "num_channels": 3,
        "torch_dtype": "float32",
    }
    with open(os.path.join(out_dir, "config.json"), "w") as handle:
        json.dump(config, handle, indent=2)

    preprocessor = {
        "do_normalize": True,
        "do_rescale": True,
        "do_resize": True,
        "image_mean": [0.485, 0.456, 0.406],
        "image_std": [0.229, 0.224, 0.225],
        "resample": 2,
        "rescale_factor": 0.00392156862745098,
        "size": {"height": INPUT_SIZE, "width": INPUT_SIZE},
    }
    with open(os.path.join(out_dir, "preprocessor_config.json"), "w") as handle:
        json.dump(preprocessor, handle, indent=2)


if __name__ == "__main__":
    main()
