from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class AcceleratorPreference(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    ACCELERATOR_PREFERENCE_AUTO: _ClassVar[AcceleratorPreference]
    ACCELERATOR_PREFERENCE_ANE: _ClassVar[AcceleratorPreference]
    ACCELERATOR_PREFERENCE_GPU: _ClassVar[AcceleratorPreference]
    ACCELERATOR_PREFERENCE_CPU: _ClassVar[AcceleratorPreference]
ACCELERATOR_PREFERENCE_AUTO: AcceleratorPreference
ACCELERATOR_PREFERENCE_ANE: AcceleratorPreference
ACCELERATOR_PREFERENCE_GPU: AcceleratorPreference
ACCELERATOR_PREFERENCE_CPU: AcceleratorPreference

class HardwareProfile(_message.Message):
    __slots__ = ("chip", "has_neural_engine", "acceleration_mode", "total_memory_bytes", "core_count", "performance_cores", "efficiency_cores", "architecture", "platform")
    CHIP_FIELD_NUMBER: _ClassVar[int]
    HAS_NEURAL_ENGINE_FIELD_NUMBER: _ClassVar[int]
    ACCELERATION_MODE_FIELD_NUMBER: _ClassVar[int]
    TOTAL_MEMORY_BYTES_FIELD_NUMBER: _ClassVar[int]
    CORE_COUNT_FIELD_NUMBER: _ClassVar[int]
    PERFORMANCE_CORES_FIELD_NUMBER: _ClassVar[int]
    EFFICIENCY_CORES_FIELD_NUMBER: _ClassVar[int]
    ARCHITECTURE_FIELD_NUMBER: _ClassVar[int]
    PLATFORM_FIELD_NUMBER: _ClassVar[int]
    chip: str
    has_neural_engine: bool
    acceleration_mode: str
    total_memory_bytes: int
    core_count: int
    performance_cores: int
    efficiency_cores: int
    architecture: str
    platform: str
    def __init__(self, chip: _Optional[str] = ..., has_neural_engine: _Optional[bool] = ..., acceleration_mode: _Optional[str] = ..., total_memory_bytes: _Optional[int] = ..., core_count: _Optional[int] = ..., performance_cores: _Optional[int] = ..., efficiency_cores: _Optional[int] = ..., architecture: _Optional[str] = ..., platform: _Optional[str] = ...) -> None: ...

class AcceleratorInfo(_message.Message):
    __slots__ = ("name", "type", "available")
    NAME_FIELD_NUMBER: _ClassVar[int]
    TYPE_FIELD_NUMBER: _ClassVar[int]
    AVAILABLE_FIELD_NUMBER: _ClassVar[int]
    name: str
    type: AcceleratorPreference
    available: bool
    def __init__(self, name: _Optional[str] = ..., type: _Optional[_Union[AcceleratorPreference, str]] = ..., available: _Optional[bool] = ...) -> None: ...

class HardwareProfileResult(_message.Message):
    __slots__ = ("profile", "accelerators")
    PROFILE_FIELD_NUMBER: _ClassVar[int]
    ACCELERATORS_FIELD_NUMBER: _ClassVar[int]
    profile: HardwareProfile
    accelerators: _containers.RepeatedCompositeFieldContainer[AcceleratorInfo]
    def __init__(self, profile: _Optional[_Union[HardwareProfile, _Mapping]] = ..., accelerators: _Optional[_Iterable[_Union[AcceleratorInfo, _Mapping]]] = ...) -> None: ...
