"""Per-request option dataclasses, one per modality, with the v3 spec's names and defaults.

Every field is optional. Defaults come from the ``rac_default`` annotations in
``idl/llm_options.proto`` and friends, so the value a caller gets when they say nothing is
the same value commons applies to an unset wire field, and the same across all eight SDKs.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import IntEnum
from typing import List, Optional

from .inputs import AudioFormat, ImageInput, InferenceFramework, JsonSchema, ToolDefinition

__all__ = [
    "DiarizationOptions",
    "EmbedOptions",
    "Endpointing",
    "Environment",
    "ImageMode",
    "ImageModeKind",
    "ImageOptions",
    "Interruption",
    "LlmOptions",
    "LoadOptions",
    "PoolingMode",
    "RagConfig",
    "ReasoningMode",
    "ReasoningOptions",
    "SegmentationOptions",
    "StructuredOutput",
    "SttOptions",
    "ToolChoice",
    "ToolChoiceMode",
    "TtsOptions",
    "TurnHandlingOptions",
    "VadOptions",
]


class Environment(IntEnum):
    """Deployment environment passed to :func:`runanywhere.initialize`.

    Values mirror ``runanywhere.v1.SDKEnvironment``.
    """

    UNSPECIFIED = 0
    DEVELOPMENT = 1
    PRODUCTION = 3


class ReasoningMode(IntEnum):
    """Whether the model is allowed to think before answering."""

    ON = 2
    OFF = 1


@dataclass
class ReasoningOptions:
    """Reasoning controls: suppress thinking, or stream the thoughts to the caller."""

    mode: ReasoningMode = ReasoningMode.ON
    include_in_output: bool = False
    pattern: Optional[str] = None


@dataclass
class StructuredOutput:
    """JSON-Schema constraint applied to decoding."""

    schema: JsonSchema
    strict: bool = True


class ToolChoiceMode(IntEnum):
    """How the model may use the available tools."""

    AUTO = 0
    NONE = 1
    REQUIRED = 2
    FORCED = 3


@dataclass(frozen=True)
class ToolChoice:
    """Tool-selection policy for a generation."""

    mode: ToolChoiceMode = ToolChoiceMode.AUTO
    name: Optional[str] = None

    @classmethod
    def forced(cls, name: str) -> "ToolChoice":
        """Require the model to call the named tool."""
        return cls(mode=ToolChoiceMode.FORCED, name=name)


@dataclass
class LlmOptions:
    """Generation controls for ``llm`` and ``vlm``."""

    model: Optional[str] = None
    max_output_tokens: int = 512
    temperature: float = 0.7
    top_p: float = 1.0
    top_k: Optional[int] = None
    min_p: Optional[float] = None
    frequency_penalty: Optional[float] = None
    presence_penalty: Optional[float] = None
    repetition_penalty: Optional[float] = None
    seed: Optional[int] = None
    stop_sequences: List[str] = field(default_factory=list)
    system_prompt: Optional[str] = None
    reasoning: Optional[ReasoningOptions] = None
    structured_output: Optional[StructuredOutput] = None
    tools: List[ToolDefinition] = field(default_factory=list)
    tool_choice: ToolChoice = field(default_factory=lambda: ToolChoice(ToolChoiceMode.AUTO))
    max_tool_calls: int = 5


@dataclass
class SttOptions:
    """Transcription controls.

    ``model`` is a Python addition: this SDK has no control plane to assign one, so the
    caller names the model it wants.
    """

    language: Optional[str] = None
    punctuation: bool = True
    word_timestamps: bool = True
    diarization: bool = False
    max_speakers: Optional[int] = None
    translate_to_english: bool = False
    model: Optional[str] = None


@dataclass
class TtsOptions:
    """Synthesis controls."""

    voice: Optional[str] = None
    language: str = "en-US"
    speed: float = 1.0
    pitch: float = 1.0
    format: AudioFormat = AudioFormat.PCM
    sample_rate: int = 22050
    model: Optional[str] = None


@dataclass
class VadOptions:
    """Speech-detection controls."""

    activation_threshold: Optional[float] = None
    min_speech_ms: int = 100
    min_silence_ms: int = 300
    prefix_padding_ms: int = 0
    model: Optional[str] = None


class PoolingMode(IntEnum):
    """Token-pooling strategy used to build one vector per input."""

    MEAN = 0
    CLS = 1
    MAX = 2


@dataclass
class EmbedOptions:
    """Embedding controls."""

    normalize: bool = True
    pooling: PoolingMode = PoolingMode.MEAN
    model: Optional[str] = None


class ImageModeKind(IntEnum):
    """Whether an image request generates from scratch or fills a masked region."""

    GENERATE = 0
    INPAINT = 1


@dataclass(frozen=True)
class ImageMode:
    """Image generation mode; ``inpaint`` carries the source image and its mask."""

    kind: ImageModeKind = ImageModeKind.GENERATE
    input: Optional[ImageInput] = None
    mask: Optional[ImageInput] = None

    @classmethod
    def inpaint(cls, input: ImageInput, mask: ImageInput) -> "ImageMode":
        """Fill the masked region of ``input``."""
        return cls(kind=ImageModeKind.INPAINT, input=input, mask=mask)


@dataclass
class ImageOptions:
    """Image generation controls."""

    negative_prompt: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None
    steps: Optional[int] = None
    guidance_scale: Optional[float] = None
    seed: Optional[int] = None
    mode: ImageMode = field(default_factory=lambda: ImageMode(ImageModeKind.GENERATE))
    report_partials: bool = False
    model: Optional[str] = None


@dataclass
class DiarizationOptions:
    """Speaker-diarization controls."""

    threshold: Optional[float] = None
    minimum_duration_ms: Optional[int] = None
    merge_gap_ms: Optional[int] = None
    model: Optional[str] = None


@dataclass
class SegmentationOptions:
    """Semantic-segmentation controls."""

    include_diagnostic_image: bool = False
    model: Optional[str] = None


@dataclass
class Endpointing:
    """How long to wait after speech stops before the agent takes its turn."""

    min_delay_ms: int = 500
    max_delay_ms: int = 3000


@dataclass
class Interruption:
    """Whether the user's speech cuts the agent off mid-utterance."""

    enabled: bool = True
    min_duration_ms: int = 500


@dataclass
class TurnHandlingOptions:
    """Turn-taking behaviour of a voice session."""

    endpointing: Endpointing = field(default_factory=Endpointing)
    interruption: Interruption = field(default_factory=Interruption)


@dataclass
class RagConfig:
    """Chunking, retrieval and persistence settings of a RAG session."""

    top_k: int = 5
    chunk_size: int = 512
    chunk_overlap: int = 64
    similarity_threshold: Optional[float] = None
    persist_path: Optional[str] = None


@dataclass
class LoadOptions:
    """Placement knobs applied when a model is loaded."""

    framework: Optional[InferenceFramework] = None
    context_length: Optional[int] = None
    threads: Optional[int] = None
    use_gpu: Optional[bool] = None
