import {
  ConnectSession,
  type ConnectHost,
  type ConnectState,
} from '@runanywhere/core';

const session = new ConnectSession('React Native device');

export const ConnectService = {
  session,
  getSnapshot: (): ConnectState => session.state,
  subscribe: (listener: () => void): (() => void) =>
    session.subscribe(() => listener()),
  findHosts: (): Promise<void> => session.startBrowsing(),
  connect: (host: ConnectHost): Promise<void> => session.connect(host),
  disconnect: (): void => session.disconnect(),
};
