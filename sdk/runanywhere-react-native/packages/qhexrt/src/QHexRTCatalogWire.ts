import {
  type ModelInfo,
  ModelInfo as ModelInfoCodec,
  type RegisterModelFromUrlRequest,
  RegisterModelFromUrlRequest as RegisterModelFromUrlRequestCodec,
} from '@runanywhere/proto-ts/model_types';

function bytesToArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength
  ) as ArrayBuffer;
}

/** Generated-enum/protobuf transport only; all QHexRT policy stays native. */
export const QHexRTCatalogWire = {
  encodeRequest(request: RegisterModelFromUrlRequest): ArrayBuffer {
    return bytesToArrayBuffer(
      RegisterModelFromUrlRequestCodec.encode(request).finish()
    );
  },

  decodeModel(buffer: ArrayBuffer): ModelInfo | null {
    if (buffer.byteLength === 0) return null;
    return ModelInfoCodec.decode(new Uint8Array(buffer));
  },
};
