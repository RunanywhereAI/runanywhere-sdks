import { handleControlPlaneRelay } from '../../server/control-plane-relay.js';

/** Vercel Web-standard Node handler; the environment credential stays server-side. */
const handler = {
  async fetch(request: Request): Promise<Response> {
    return handleControlPlaneRelay(request, {
      apiKey: process.env.RUNANYWHERE_API_KEY,
    });
  },
};

export default handler;
