from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class DeviceAffinity(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    DEVICE_AFFINITY_UNSPECIFIED: _ClassVar[DeviceAffinity]
    DEVICE_AFFINITY_ANY: _ClassVar[DeviceAffinity]
    DEVICE_AFFINITY_CPU: _ClassVar[DeviceAffinity]
    DEVICE_AFFINITY_GPU: _ClassVar[DeviceAffinity]
    DEVICE_AFFINITY_ANE: _ClassVar[DeviceAffinity]

class EdgePolicy(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    EDGE_POLICY_UNSPECIFIED: _ClassVar[EdgePolicy]
    EDGE_POLICY_BLOCK: _ClassVar[EdgePolicy]
    EDGE_POLICY_DROP_OLDEST: _ClassVar[EdgePolicy]
    EDGE_POLICY_DROP_NEWEST: _ClassVar[EdgePolicy]
DEVICE_AFFINITY_UNSPECIFIED: DeviceAffinity
DEVICE_AFFINITY_ANY: DeviceAffinity
DEVICE_AFFINITY_CPU: DeviceAffinity
DEVICE_AFFINITY_GPU: DeviceAffinity
DEVICE_AFFINITY_ANE: DeviceAffinity
EDGE_POLICY_UNSPECIFIED: EdgePolicy
EDGE_POLICY_BLOCK: EdgePolicy
EDGE_POLICY_DROP_OLDEST: EdgePolicy
EDGE_POLICY_DROP_NEWEST: EdgePolicy

class PipelineSpec(_message.Message):
    __slots__ = ("name", "operators", "edges", "options")
    NAME_FIELD_NUMBER: _ClassVar[int]
    OPERATORS_FIELD_NUMBER: _ClassVar[int]
    EDGES_FIELD_NUMBER: _ClassVar[int]
    OPTIONS_FIELD_NUMBER: _ClassVar[int]
    name: str
    operators: _containers.RepeatedCompositeFieldContainer[OperatorSpec]
    edges: _containers.RepeatedCompositeFieldContainer[EdgeSpec]
    options: PipelineOptions
    def __init__(self, name: _Optional[str] = ..., operators: _Optional[_Iterable[_Union[OperatorSpec, _Mapping]]] = ..., edges: _Optional[_Iterable[_Union[EdgeSpec, _Mapping]]] = ..., options: _Optional[_Union[PipelineOptions, _Mapping]] = ...) -> None: ...

class OperatorSpec(_message.Message):
    __slots__ = ("name", "type", "params", "pinned_engine", "model_id", "device")
    class ParamsEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    NAME_FIELD_NUMBER: _ClassVar[int]
    TYPE_FIELD_NUMBER: _ClassVar[int]
    PARAMS_FIELD_NUMBER: _ClassVar[int]
    PINNED_ENGINE_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    DEVICE_FIELD_NUMBER: _ClassVar[int]
    name: str
    type: str
    params: _containers.ScalarMap[str, str]
    pinned_engine: str
    model_id: str
    device: DeviceAffinity
    def __init__(self, name: _Optional[str] = ..., type: _Optional[str] = ..., params: _Optional[_Mapping[str, str]] = ..., pinned_engine: _Optional[str] = ..., model_id: _Optional[str] = ..., device: _Optional[_Union[DeviceAffinity, str]] = ...) -> None: ...

class EdgeSpec(_message.Message):
    __slots__ = ("to", "capacity", "policy")
    FROM_FIELD_NUMBER: _ClassVar[int]
    TO_FIELD_NUMBER: _ClassVar[int]
    CAPACITY_FIELD_NUMBER: _ClassVar[int]
    POLICY_FIELD_NUMBER: _ClassVar[int]
    to: str
    capacity: int
    policy: EdgePolicy
    def __init__(self, to: _Optional[str] = ..., capacity: _Optional[int] = ..., policy: _Optional[_Union[EdgePolicy, str]] = ..., **kwargs) -> None: ...

class PipelineOptions(_message.Message):
    __slots__ = ("latency_budget_ms", "emit_metrics", "strict_validation")
    LATENCY_BUDGET_MS_FIELD_NUMBER: _ClassVar[int]
    EMIT_METRICS_FIELD_NUMBER: _ClassVar[int]
    STRICT_VALIDATION_FIELD_NUMBER: _ClassVar[int]
    latency_budget_ms: int
    emit_metrics: bool
    strict_validation: bool
    def __init__(self, latency_budget_ms: _Optional[int] = ..., emit_metrics: _Optional[bool] = ..., strict_validation: _Optional[bool] = ...) -> None: ...
