import { SDKEvent, type SDKEvent as ProtoSDKEvent } from '@runanywhere/proto-ts/sdk_events';
import {
  setDefaultProtoTransport,
  type ProtoEventTransport,
  type SDKEventHandler,
  type SDKEventUnsubscribe,
} from '../Foundation/EventBus';
import { clientFor } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

export class SDKEventStreamAdapter implements ProtoEventTransport {
  constructor(private readonly client: WorkerProtoClient) {}

  subscribe(handler: SDKEventHandler): SDKEventUnsubscribe | null {
    return this.client.subscribe(
      'rac_sdk_event_subscribe',
      { fn: 'rac_sdk_event_unsubscribe' },
      [Arg.streamCb(false), Arg.num(0)],
      SDKEvent,
      handler,
    );
  }

  publish(event: ProtoSDKEvent): boolean {
    const bytes = SDKEvent.encode(event).finish();
    void this.client.callRc('rac_sdk_event_publish_proto', [Arg.bytes(bytes)]);
    return true;
  }
}

export function installSDKEventTransport(): void {
  setDefaultProtoTransport(() => {
    const client = clientFor('commons');
    return client ? new SDKEventStreamAdapter(client) : null;
  });
}
