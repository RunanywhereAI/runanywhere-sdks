import voice_events_pb2 as _voice_events_pb2
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class VoiceAgentRequest(_message.Message):
    __slots__ = ("event_filter",)
    EVENT_FILTER_FIELD_NUMBER: _ClassVar[int]
    event_filter: str
    def __init__(self, event_filter: _Optional[str] = ...) -> None: ...
