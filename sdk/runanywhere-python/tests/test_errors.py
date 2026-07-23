"""Tests for runanywhere.errors: category mapping, raise_for_rac, is_expected, factories."""

from __future__ import annotations

import pytest

# Import via the package (its __init__ is lazy — it does not load the native core), so this
# test works whether ``runanywhere`` is the source tree or an installed wheel run from a
# relocated ``tests/`` dir (the CI hermetic step copies tests out of the source tree).
from runanywhere.errors import (
    ErrorCategory,
    ErrorCode,
    SDKException,
    as_sdk_exception,
    category_for_code,
    is_sdk_exception,
    raise_for_rac,
)


# --------------------------------------------------------------------------- #
# Enum values                                                                  #
# --------------------------------------------------------------------------- #
def test_error_code_values():
    assert ErrorCode.UNSPECIFIED == 0
    assert ErrorCode.NOT_INITIALIZED == 100
    assert ErrorCode.MODEL_NOT_FOUND == 110
    assert ErrorCode.MODEL_LOAD_FAILED == 111
    assert ErrorCode.GENERATION_FAILED == 130
    assert ErrorCode.STORAGE_ERROR == 182
    assert ErrorCode.INVALID_STATE == 231
    assert ErrorCode.SERVICE_NOT_AVAILABLE == 232
    assert ErrorCode.PROCESSING_FAILED == 234
    assert ErrorCode.INVALID_INPUT == 251
    assert ErrorCode.INVALID_ARGUMENT == 259
    assert ErrorCode.CANCELLED == 380
    assert ErrorCode.NOT_IMPLEMENTED == 800
    assert ErrorCode.UNKNOWN == 804


def test_error_category_values():
    assert ErrorCategory.UNSPECIFIED == 0
    assert ErrorCategory.NETWORK == 1
    assert ErrorCategory.VALIDATION == 2
    assert ErrorCategory.MODEL == 3
    assert ErrorCategory.COMPONENT == 4
    assert ErrorCategory.IO == 5
    assert ErrorCategory.AUTH == 6
    assert ErrorCategory.INTERNAL == 7
    assert ErrorCategory.CONFIGURATION == 8


# --------------------------------------------------------------------------- #
# category_for_code range table (verbatim port)                               #
# --------------------------------------------------------------------------- #
@pytest.mark.parametrize(
    "code,expected",
    [
        (0, ErrorCategory.UNSPECIFIED),
        (100, ErrorCategory.CONFIGURATION),
        (109, ErrorCategory.CONFIGURATION),
        (110, ErrorCategory.MODEL),
        (111, ErrorCategory.MODEL),
        (129, ErrorCategory.MODEL),
        (130, ErrorCategory.COMPONENT),
        (149, ErrorCategory.COMPONENT),
        (150, ErrorCategory.NETWORK),
        (179, ErrorCategory.NETWORK),
        (180, ErrorCategory.IO),
        (182, ErrorCategory.IO),
        (219, ErrorCategory.IO),
        (220, ErrorCategory.INTERNAL),
        (229, ErrorCategory.INTERNAL),
        (230, ErrorCategory.COMPONENT),
        (231, ErrorCategory.COMPONENT),
        (249, ErrorCategory.COMPONENT),
        (250, ErrorCategory.VALIDATION),
        (259, ErrorCategory.VALIDATION),
        (279, ErrorCategory.VALIDATION),
        (280, ErrorCategory.IO),
        (299, ErrorCategory.IO),
        (300, ErrorCategory.COMPONENT),
        (319, ErrorCategory.COMPONENT),
        (320, ErrorCategory.AUTH),
        (349, ErrorCategory.AUTH),
        (350, ErrorCategory.IO),
        (369, ErrorCategory.IO),
        (370, ErrorCategory.VALIDATION),
        (379, ErrorCategory.VALIDATION),
        (380, ErrorCategory.INTERNAL),
        (389, ErrorCategory.INTERNAL),
        (400, ErrorCategory.COMPONENT),
        (499, ErrorCategory.COMPONENT),
        (500, ErrorCategory.CONFIGURATION),
        (599, ErrorCategory.CONFIGURATION),
        (600, ErrorCategory.COMPONENT),
        (699, ErrorCategory.COMPONENT),
        (700, ErrorCategory.INTERNAL),
        (800, ErrorCategory.INTERNAL),
        (804, ErrorCategory.INTERNAL),
        (999, ErrorCategory.INTERNAL),
        (1000, ErrorCategory.UNSPECIFIED),
        (-5, ErrorCategory.UNSPECIFIED),
    ],
)
def test_category_for_code(code, expected):
    assert category_for_code(code) == expected


def test_category_defaults_applied_in_ctor():
    # No explicit category -> derived from code via category_for_code.
    assert SDKException(ErrorCode.MODEL_NOT_FOUND, "x").category == ErrorCategory.MODEL
    assert SDKException(ErrorCode.INVALID_INPUT, "x").category == ErrorCategory.VALIDATION


# --------------------------------------------------------------------------- #
# c_abi_code derivation                                                        #
# --------------------------------------------------------------------------- #
def test_c_abi_code_auto_negative():
    e = SDKException(ErrorCode.MODEL_LOAD_FAILED, "x")
    assert e.c_abi_code == -111


def test_c_abi_code_unspecified_is_none():
    # code 0 is not in (0, 899] range -> no c_abi_code.
    assert SDKException(ErrorCode.UNSPECIFIED, "x").c_abi_code is None


def test_c_abi_code_explicit_wins():
    e = SDKException(ErrorCode.INVALID_ARGUMENT, "x", c_abi_code=-259)
    assert e.c_abi_code == -259


# --------------------------------------------------------------------------- #
# raise_for_rac                                                                #
# --------------------------------------------------------------------------- #
def test_raise_for_rac_maps_minus_111_to_model_load_failed():
    with pytest.raises(SDKException) as ei:
        raise_for_rac(-111)
    e = ei.value
    assert e.code == ErrorCode.MODEL_LOAD_FAILED
    assert e.c_abi_code == -111
    assert e.category == ErrorCategory.MODEL


def test_raise_for_rac_unknown_code_falls_back_to_unknown():
    with pytest.raises(SDKException) as ei:
        raise_for_rac(-9999)
    e = ei.value
    assert e.code == ErrorCode.UNKNOWN
    assert e.c_abi_code == -9999


def test_raise_for_rac_custom_message():
    with pytest.raises(SDKException) as ei:
        raise_for_rac(-380, "user cancelled")
    e = ei.value
    assert e.code == ErrorCode.CANCELLED
    assert str(e) == "user cancelled"
    assert e.c_abi_code == -380
    assert e.category == ErrorCategory.INTERNAL


# --------------------------------------------------------------------------- #
# recovery_suggestion                                                          #
# --------------------------------------------------------------------------- #
def test_recovery_suggestions():
    assert (
        SDKException(ErrorCode.NOT_INITIALIZED, "x").recovery_suggestion
        == "Initialize the SDK (RunAnywhere.initialize()) before using it."
    )
    assert (
        SDKException(ErrorCode.MODEL_NOT_FOUND, "x").recovery_suggestion
        == "Ensure the model is downloaded and the path/id is correct."
    )
    assert (
        SDKException(ErrorCode.MODEL_LOAD_FAILED, "x").recovery_suggestion
        == "Check the model file is valid and compatible."
    )
    assert (
        SDKException(ErrorCode.STORAGE_ERROR, "x").recovery_suggestion
        == "Free up storage space and try again."
    )
    assert SDKException(ErrorCode.GENERATION_FAILED, "x").recovery_suggestion is None


# --------------------------------------------------------------------------- #
# is_expected                                                                  #
# --------------------------------------------------------------------------- #
def test_is_expected_only_for_cancelled():
    assert SDKException(ErrorCode.CANCELLED, "x").is_expected is True
    for code in (
        ErrorCode.UNSPECIFIED,
        ErrorCode.NOT_INITIALIZED,
        ErrorCode.MODEL_NOT_FOUND,
        ErrorCode.MODEL_LOAD_FAILED,
        ErrorCode.GENERATION_FAILED,
        ErrorCode.INVALID_INPUT,
        ErrorCode.UNKNOWN,
    ):
        assert SDKException(code, "x").is_expected is False


# --------------------------------------------------------------------------- #
# factories                                                                    #
# --------------------------------------------------------------------------- #
def test_factory_not_initialized():
    e = SDKException.not_initialized()
    assert e.code == ErrorCode.NOT_INITIALIZED
    assert e.category == ErrorCategory.COMPONENT
    assert str(e) == "SDK not initialized"
    e2 = SDKException.not_initialized("Embedder")
    assert str(e2) == "Embedder not initialized"


def test_factory_invalid_input():
    assert str(SDKException.invalid_input()) == "Invalid input"
    e = SDKException.invalid_input("bad json")
    assert str(e) == "Invalid input: bad json"
    assert e.code == ErrorCode.INVALID_INPUT
    assert e.category == ErrorCategory.VALIDATION


def test_factory_validation_failed():
    e = SDKException.validation_failed(field_path="ToolSpec.name", message="required")
    assert e.code == ErrorCode.INVALID_ARGUMENT
    assert e.category == ErrorCategory.VALIDATION
    assert e.c_abi_code == -259
    assert e.field_path == "ToolSpec.name"
    assert str(e) == "required"


def test_factory_model_not_found():
    assert str(SDKException.model_not_found()) == "Model not found"
    e = SDKException.model_not_found("llama")
    assert str(e) == "Model not found: llama"
    assert e.code == ErrorCode.MODEL_NOT_FOUND
    assert e.category == ErrorCategory.MODEL


def test_factory_model_load_failed():
    e = SDKException.model_load_failed("llama", ValueError("bad header"))
    assert e.code == ErrorCode.MODEL_LOAD_FAILED
    assert str(e) == "Failed to load model: llama"
    assert e.nested_message == "bad header"
    assert e.c_abi_code == -111
    assert SDKException.model_load_failed().nested_message is None
    assert str(SDKException.model_load_failed()) == "Failed to load model"


def test_factory_generation_failed():
    e = SDKException.generation_failed("oops", RuntimeError("stack"))
    assert e.code == ErrorCode.GENERATION_FAILED
    assert str(e) == "oops"
    assert e.nested_message == "stack"
    assert str(SDKException.generation_failed()) == "Generation failed"


def test_factory_invalid_state():
    e = SDKException.invalid_state("busy")
    assert e.code == ErrorCode.INVALID_STATE
    assert e.category == ErrorCategory.INTERNAL
    assert str(e) == "busy"
    assert str(SDKException.invalid_state()) == "Invalid state"


def test_factory_not_implemented():
    assert str(SDKException.not_implemented()) == "Not implemented"
    e = SDKException.not_implemented("streaming")
    assert str(e) == "streaming not implemented"
    assert e.code == ErrorCode.NOT_IMPLEMENTED


def test_factory_cancelled():
    e = SDKException.cancelled()
    assert e.code == ErrorCode.CANCELLED
    assert e.category == ErrorCategory.INTERNAL
    assert str(e) == "Operation cancelled"
    assert e.is_expected is True
    assert str(SDKException.cancelled("stop")) == "stop"


def test_factory_unknown():
    e = SDKException.unknown("weird", KeyError("k"))
    assert e.code == ErrorCode.UNKNOWN
    assert str(e) == "weird"
    assert e.nested_message == "'k'"
    assert str(SDKException.unknown()) == "Unknown error"


def test_of_passthrough():
    e = SDKException.of(
        ErrorCode.PROCESSING_FAILED,
        "hi",
        category=ErrorCategory.COMPONENT,
        c_abi_code=-234,
        nested_message="nm",
        field_path="fp",
    )
    assert e.code == ErrorCode.PROCESSING_FAILED
    assert e.category == ErrorCategory.COMPONENT
    assert e.c_abi_code == -234
    assert e.nested_message == "nm"
    assert e.field_path == "fp"


# --------------------------------------------------------------------------- #
# guards / coercion                                                            #
# --------------------------------------------------------------------------- #
def test_is_sdk_exception():
    assert is_sdk_exception(SDKException.cancelled()) is True
    assert is_sdk_exception(ValueError("x")) is False
    assert is_sdk_exception("nope") is False


def test_as_sdk_exception():
    e = SDKException.cancelled()
    assert as_sdk_exception(e) is e

    from_err = as_sdk_exception(ValueError("boom"))
    assert from_err.code == ErrorCode.UNKNOWN
    assert str(from_err) == "boom"
    assert from_err.nested_message == "boom"

    from_str = as_sdk_exception("plain")
    assert from_str.code == ErrorCode.UNKNOWN
    assert str(from_str) == "plain"

    from_other = as_sdk_exception(123)
    assert from_other.code == ErrorCode.UNKNOWN
    assert str(from_other) == "123"


def test_sdk_exception_is_exception():
    assert isinstance(SDKException.cancelled(), Exception)
