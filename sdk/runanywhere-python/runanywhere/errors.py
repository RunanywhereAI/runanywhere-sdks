"""SDKException, the single throwable type the SDK raises (port of errors.ts)."""

from __future__ import annotations

from enum import IntEnum
from typing import NoReturn


class ErrorCode(IntEnum):
    """Canonical numeric error codes from ``idl/errors.proto`` (positive abs of rac_result_t).

    Exhaustive relative to the IDL enum. Keep in sync with ``idl/errors.proto`` /
    ``rac_error.h`` — prefer regenerating when the IDL changes.
    """

    UNSPECIFIED = 0
    NOT_INITIALIZED = 100
    ALREADY_INITIALIZED = 101
    INITIALIZATION_FAILED = 102
    INVALID_CONFIGURATION = 103
    INVALID_API_KEY = 104
    ENVIRONMENT_MISMATCH = 105
    INVALID_PARAMETER = 106
    MODEL_NOT_FOUND = 110
    MODEL_LOAD_FAILED = 111
    MODEL_VALIDATION_FAILED = 112
    MODEL_INCOMPATIBLE = 113
    INVALID_MODEL_FORMAT = 114
    MODEL_STORAGE_CORRUPTED = 115
    MODEL_NOT_LOADED = 116
    GENERATION_FAILED = 130
    GENERATION_TIMEOUT = 131
    CONTEXT_TOO_LONG = 132
    TOKEN_LIMIT_EXCEEDED = 133
    COST_LIMIT_EXCEEDED = 134
    INFERENCE_FAILED = 135
    GENERATION_CANCELLED = 136
    NETWORK_UNAVAILABLE = 150
    NETWORK_ERROR = 151
    REQUEST_FAILED = 152
    DOWNLOAD_FAILED = 153
    SERVER_ERROR = 154
    TIMEOUT = 155
    INVALID_RESPONSE = 156
    HTTP_ERROR = 157
    CONNECTION_LOST = 158
    PARTIAL_DOWNLOAD = 159
    HTTP_REQUEST_FAILED = 160
    HTTP_NOT_SUPPORTED = 161
    INSUFFICIENT_STORAGE = 180
    STORAGE_FULL = 181
    STORAGE_ERROR = 182
    FILE_NOT_FOUND = 183
    FILE_READ_FAILED = 184
    FILE_WRITE_FAILED = 185
    PERMISSION_DENIED = 186
    DELETE_FAILED = 187
    MOVE_FAILED = 188
    DIRECTORY_CREATION_FAILED = 189
    DIRECTORY_NOT_FOUND = 190
    INVALID_PATH = 191
    INVALID_FILE_NAME = 192
    TEMP_FILE_CREATION_FAILED = 193
    HARDWARE_UNSUPPORTED = 220
    INSUFFICIENT_MEMORY = 221
    COMPONENT_NOT_READY = 230
    INVALID_STATE = 231
    SERVICE_NOT_AVAILABLE = 232
    SERVICE_BUSY = 233
    PROCESSING_FAILED = 234
    START_FAILED = 235
    NOT_SUPPORTED = 236
    VALIDATION_FAILED = 250
    INVALID_INPUT = 251
    INVALID_FORMAT = 252
    EMPTY_INPUT = 253
    TEXT_TOO_LONG = 254
    INVALID_SSML = 255
    INVALID_SPEAKING_RATE = 256
    INVALID_PITCH = 257
    INVALID_VOLUME = 258
    INVALID_ARGUMENT = 259
    NULL_POINTER = 260
    BUFFER_TOO_SMALL = 261
    OUTPUT_TRUNCATED = 262
    AUDIO_FORMAT_NOT_SUPPORTED = 280
    AUDIO_SESSION_FAILED = 281
    MICROPHONE_PERMISSION_DENIED = 282
    INSUFFICIENT_AUDIO_DATA = 283
    EMPTY_AUDIO_BUFFER = 284
    AUDIO_SESSION_ACTIVATION_FAILED = 285
    LANGUAGE_NOT_SUPPORTED = 300
    VOICE_NOT_AVAILABLE = 301
    STREAMING_NOT_SUPPORTED = 302
    STREAM_CANCELLED = 303
    AUTHENTICATION_FAILED = 320
    UNAUTHORIZED = 321
    FORBIDDEN = 322
    KEYCHAIN_ERROR = 330
    ENCODING_ERROR = 331
    DECODING_ERROR = 332
    SECURE_STORAGE_FAILED = 333
    EXTRACTION_FAILED = 350
    CHECKSUM_MISMATCH = 351
    UNSUPPORTED_ARCHIVE = 352
    CALIBRATION_FAILED = 370
    CALIBRATION_TIMEOUT = 371
    CANCELLED = 380
    MODULE_NOT_FOUND = 400
    MODULE_ALREADY_REGISTERED = 401
    MODULE_LOAD_FAILED = 402
    SERVICE_NOT_FOUND = 410
    SERVICE_ALREADY_REGISTERED = 411
    SERVICE_CREATE_FAILED = 412
    CAPABILITY_NOT_FOUND = 420
    PROVIDER_NOT_FOUND = 421
    NO_CAPABLE_PROVIDER = 422
    NOT_FOUND = 423
    ADAPTER_NOT_SET = 500
    BACKEND_NOT_FOUND = 600
    BACKEND_NOT_READY = 601
    BACKEND_INIT_FAILED = 602
    BACKEND_BUSY = 603
    BACKEND_UNAVAILABLE = 604
    RUNTIME_UNAVAILABLE = 605
    BACKEND_ERROR = 606
    INVALID_HANDLE = 610
    EVENT_INVALID_CATEGORY = 700
    EVENT_SUBSCRIPTION_FAILED = 701
    EVENT_PUBLISH_FAILED = 702
    NOT_IMPLEMENTED = 800
    FEATURE_NOT_AVAILABLE = 801
    FRAMEWORK_NOT_AVAILABLE = 802
    UNSUPPORTED_MODALITY = 803
    UNKNOWN = 804
    INTERNAL = 805
    ABI_VERSION_MISMATCH = 810
    CAPABILITY_UNSUPPORTED = 811
    PLUGIN_DUPLICATE = 812
    PLUGIN_LOAD_FAILED = 820
    PLUGIN_BUSY = 821
    WASM_LOAD_FAILED = 900
    WASM_NOT_LOADED = 901
    WASM_CALLBACK_ERROR = 902
    WASM_MEMORY_ERROR = 903


class ErrorCategory(IntEnum):
    """Canonical error categories from idl/errors.proto."""

    UNSPECIFIED = 0
    NETWORK = 1
    VALIDATION = 2
    MODEL = 3
    COMPONENT = 4
    IO = 5
    AUTH = 6
    INTERNAL = 7
    CONFIGURATION = 8


def category_for_code(code: int) -> ErrorCategory:
    """Map an ErrorCode (positive) or ``rac_result_t`` (negative) to its ErrorCategory.

    Faithful port of commons ``rac_result_to_proto_category`` in
    ``rac_proto_adapters.cpp``. Unmapped failure codes return INTERNAL (not
    UNSPECIFIED). AUTH is only 320–329; security codes 330–349 fall through to
    INTERNAL, matching the C ABI.
    """
    # Normalize to negative rac_result_t for the commons range table.
    if code > 0:
        n = -code
    else:
        n = code
    if n >= 0:
        return ErrorCategory.UNSPECIFIED
    if -179 <= n <= -150:
        return ErrorCategory.NETWORK
    if -279 <= n <= -250:
        return ErrorCategory.VALIDATION
    if -129 <= n <= -110:
        return ErrorCategory.MODEL
    if (-219 <= n <= -180) or (-299 <= n <= -280):
        return ErrorCategory.IO
    if -329 <= n <= -320:
        return ErrorCategory.AUTH
    if -109 <= n <= -100:
        return ErrorCategory.CONFIGURATION
    if (-249 <= n <= -230) or (-319 <= n <= -300):
        return ErrorCategory.COMPONENT
    return ErrorCategory.INTERNAL


class SDKException(Exception):
    """The single throwable type the SDK raises.

    Carries the canonical ``code`` / ``category`` for cross-SDK-uniform handling,
    mirroring the Swift / Kotlin / React-Native / Web / Electron SDKs so consumer
    code can read ``e.code`` / ``e.category`` / ``e.recovery_suggestion`` /
    ``e.field_path`` uniformly.
    """

    code: ErrorCode
    category: ErrorCategory
    #: Negative rac_result_t equivalent, when applicable.
    c_abi_code: int | None
    nested_message: str | None
    #: Structured validation field path (e.g. "ToolSpec.name"), when applicable.
    field_path: str | None

    def __init__(
        self,
        code: ErrorCode,
        message: str,
        *,
        category: ErrorCategory | None = None,
        c_abi_code: int | None = None,
        nested_message: str | None = None,
        field_path: str | None = None,
    ) -> None:
        super().__init__(message or "SDK error")
        self.message = message or "SDK error"
        self.code = code
        self.category = category if category is not None else category_for_code(int(code))
        if c_abi_code is not None:
            self.c_abi_code = c_abi_code
        elif 0 < int(code) <= 899:
            self.c_abi_code = -int(code)
        else:
            self.c_abi_code = None
        self.nested_message = nested_message
        self.field_path = field_path

    @property
    def recovery_suggestion(self) -> str | None:
        """Human-readable recovery hint for common codes, mirroring the other SDKs."""
        if self.code == ErrorCode.NOT_INITIALIZED:
            return "Initialize the SDK (RunAnywhere.initialize()) before using it."
        if self.code == ErrorCode.MODEL_NOT_FOUND:
            return "Ensure the model is downloaded and the path/id is correct."
        if self.code == ErrorCode.MODEL_LOAD_FAILED:
            return "Check the model file is valid and compatible."
        if self.code == ErrorCode.STORAGE_ERROR:
            return "Free up storage space and try again."
        return None

    @property
    def is_expected(self) -> bool:
        """Expected/routine errors (cancellation) that need not be logged as errors."""
        return self.code == ErrorCode.CANCELLED

    # -- factories -----------------------------------------------------------
    @staticmethod
    def of(
        code: ErrorCode,
        message: str,
        *,
        category: ErrorCategory | None = None,
        c_abi_code: int | None = None,
        nested_message: str | None = None,
        field_path: str | None = None,
    ) -> "SDKException":
        return SDKException(
            code,
            message,
            category=category,
            c_abi_code=c_abi_code,
            nested_message=nested_message,
            field_path=field_path,
        )

    @staticmethod
    def not_initialized(component: str | None = None) -> "SDKException":
        return SDKException.of(
            ErrorCode.NOT_INITIALIZED,
            f"{component} not initialized" if component else "SDK not initialized",
            category=ErrorCategory.COMPONENT,
        )

    @staticmethod
    def invalid_input(details: str | None = None) -> "SDKException":
        return SDKException.of(
            ErrorCode.INVALID_INPUT,
            f"Invalid input: {details}" if details else "Invalid input",
        )

    @staticmethod
    def validation_failed(*, field_path: str, message: str) -> "SDKException":
        return SDKException.of(
            ErrorCode.INVALID_ARGUMENT,
            message,
            category=ErrorCategory.VALIDATION,
            c_abi_code=-259,
            field_path=field_path,
        )

    @staticmethod
    def model_not_found(model_id: str | None = None) -> "SDKException":
        return SDKException.of(
            ErrorCode.MODEL_NOT_FOUND,
            f"Model not found: {model_id}" if model_id else "Model not found",
        )

    @staticmethod
    def model_load_failed(
        model_id: str | None = None, cause: BaseException | None = None
    ) -> "SDKException":
        return SDKException.of(
            ErrorCode.MODEL_LOAD_FAILED,
            f"Failed to load model: {model_id}" if model_id else "Failed to load model",
            nested_message=str(cause) if cause is not None else None,
        )

    @staticmethod
    def generation_failed(
        details: str | None = None, cause: BaseException | None = None
    ) -> "SDKException":
        return SDKException.of(
            ErrorCode.GENERATION_FAILED,
            details if details is not None else "Generation failed",
            nested_message=str(cause) if cause is not None else None,
        )

    @staticmethod
    def storage_error(
        details: str | None = None, cause: BaseException | None = None
    ) -> "SDKException":
        return SDKException.of(
            ErrorCode.STORAGE_ERROR,
            details if details is not None else "Storage error",
            nested_message=str(cause) if cause is not None else None,
        )

    @staticmethod
    def invalid_state(details: str | None = None) -> "SDKException":
        return SDKException.of(
            ErrorCode.INVALID_STATE,
            details if details is not None else "Invalid state",
            category=ErrorCategory.INTERNAL,
        )

    @staticmethod
    def not_implemented(feature: str | None = None) -> "SDKException":
        return SDKException.of(
            ErrorCode.NOT_IMPLEMENTED,
            f"{feature} not implemented" if feature else "Not implemented",
        )

    @staticmethod
    def cancelled(message: str | None = None) -> "SDKException":
        return SDKException.of(
            ErrorCode.CANCELLED,
            message if message is not None else "Operation cancelled",
            category=ErrorCategory.INTERNAL,
        )

    @staticmethod
    def unknown(
        details: str | None = None, cause: BaseException | None = None
    ) -> "SDKException":
        return SDKException.of(
            ErrorCode.UNKNOWN,
            details if details is not None else "Unknown error",
            nested_message=str(cause) if cause is not None else None,
        )


def is_sdk_exception(e: object) -> bool:
    """Type guard: True iff ``e`` is an :class:`SDKException`."""
    return isinstance(e, SDKException)


def as_sdk_exception(e: object) -> SDKException:
    """Coerce any thrown value into an SDKException (matches RN/Web ``asSDKException``)."""
    if isinstance(e, SDKException):
        return e
    if isinstance(e, BaseException):
        return SDKException.unknown(str(e), e)
    if isinstance(e, str):
        return SDKException.unknown(e)
    return SDKException.unknown(str(e))


def raise_for_rac(rac_code: int, message: str | None = None) -> NoReturn:
    """Raise an :class:`SDKException` for a negative ``rac_result_t`` code.

    ``rac_code`` is the NEGATIVE rac_result_t returned by the native layer. The
    error code is ``ErrorCode(-rac_code)`` when that value is a known enum member,
    otherwise :attr:`ErrorCode.UNKNOWN`. The original ``rac_code`` is preserved as
    ``c_abi_code`` so callers can inspect the raw ABI value.
    """
    positive = -rac_code
    try:
        code = ErrorCode(positive)
    except ValueError:
        code = ErrorCode.UNKNOWN
    raise SDKException.of(
        code,
        message if message is not None else f"Native call failed (rac={rac_code})",
        c_abi_code=rac_code,
    )
