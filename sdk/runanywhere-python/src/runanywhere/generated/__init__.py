"""Generated protobuf modules for the RunAnywhere SDK.

The protoc-generated ``*_pb2.py`` files use top-level absolute imports
(e.g. ``import model_types_pb2``), so this package directory must be on
``sys.path`` before any ``*_pb2`` module is imported. We do that here so
that importing ``runanywhere.generated`` (or any submodule) "just works".
"""
import os
import sys

_GENERATED_DIR = os.path.dirname(os.path.abspath(__file__))
if _GENERATED_DIR not in sys.path:
    sys.path.insert(0, _GENERATED_DIR)
