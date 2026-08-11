// F3b — two-phase auth and telemetry, against the real addon, the real libcurl
// transport, and a control plane on localhost.
//
// The server here is a real HTTP backend speaking the real wire contract, not a
// stand-in for anything in the SDK: every byte it receives was built by commons
// and every byte it returns is parsed by commons. That is what makes the
// interesting claims testable without shipping credentials — a token that
// survives a process restart, a near-expiry token that refreshes, a device that
// registers with a bearer header, and an offline start that recovers on retry.
//
// Token persistence is checked across separate node processes, because a
// same-process reset leaves commons' in-memory auth state behind and would prove
// nothing about the secure store.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as http from 'node:http';
import * as os from 'node:os';
import * as path from 'node:path';
import { execFile } from 'node:child_process';
import type { AddressInfo } from 'node:net';

import { createRunAnywhere, NativeBackend, registerCatalog, clearCatalog } from '../../dist';
import type { AuthInfo, SdkEvent } from '../../dist';
import { exists, nativeAddon } from './support';

const NATIVE_PATH = process.env.RUNANYWHERE_NATIVE_PATH;
const MODEL_FILE = path.join(os.homedir(), '.runanywhere', 'models', 'smollm2-135m', 'model.gguf');
const DIST = path.resolve(__dirname, '../../dist');

const SKIP: { skip?: string } = exists(NATIVE_PATH)
  ? {}
  : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing' };

const API_KEY = 'feature-test-api-key';
const ORG_ID = 'org-feature-test';

/** One request the control plane received, kept so headers can be asserted. */
interface RecordedRequest {
  method: string | undefined;
  url: string;
  headers: http.IncomingHttpHeaders;
  body: string;
}

/** The running control plane and the knobs each case turns. */
interface ControlPlane {
  baseUrl: string;
  requests: RecordedRequest[];
  pathsHit: (prefix: string) => RecordedRequest[];
  setAuthStatus: (status: number) => void;
  setTelemetryStatus: (status: number) => void;
  close: () => Promise<void>;
}

/**
 * A control plane on localhost. Records every request so the test can assert on
 * the headers commons actually sent, and lets each case decide what the auth
 * endpoint answers.
 */
function startControlPlane(
  options: { expiresIn?: number; authStatus?: number; telemetryStatus?: number; port?: number } = {}
): Promise<ControlPlane> {
  const expiresIn = options.expiresIn ?? 3600;
  const requests: RecordedRequest[] = [];
  let authStatus = options.authStatus ?? 200;
  let telemetryStatus = options.telemetryStatus ?? 200;
  let issued = 0;

  const server = http.createServer((req, res) => {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      const url = req.url ?? '';
      requests.push({
        method: req.method,
        url,
        headers: req.headers,
        body,
      });
      const json = (status: number, payload: unknown): void => {
        res.writeHead(status, { 'content-type': 'application/json' });
        res.end(JSON.stringify(payload));
      };
      if (url === '/api/v1/auth/sdk/authenticate') {
        if (authStatus !== 200) return json(authStatus, { detail: 'auth rejected by the test' });
        issued += 1;
        return json(200, {
          access_token: `access-token-${issued}`,
          refresh_token: `refresh-token-${issued}`,
          device_id: 'backend-device-id',
          organization_id: ORG_ID,
          token_type: 'bearer',
          expires_in: expiresIn,
          device_registered: true,
        });
      }
      if (url === '/api/v1/auth/sdk/refresh') {
        issued += 1;
        return json(200, {
          access_token: `refreshed-token-${issued}`,
          refresh_token: `refresh-token-${issued}`,
          device_id: 'backend-device-id',
          organization_id: ORG_ID,
          token_type: 'bearer',
          expires_in: 3600,
        });
      }
      if (url === '/api/v1/devices/register') {
        return json(200, { device_id: 'backend-device-id', status: 'registered', sync_status: 'synced' });
      }
      if (url.startsWith('/api/v2/sdk/telemetry/')) {
        if (telemetryStatus !== 200) return json(telemetryStatus, { detail: 'telemetry rejected' });
        return json(200, { accepted: true });
      }
      // Anything else commons asks for (model assignments, health) answers
      // empty rather than 404 — those paths are not what this test is about.
      return json(200, {});
    });
  });

  return new Promise((resolve) => {
    server.listen(options.port ?? 0, '127.0.0.1', () => {
      resolve({
        baseUrl: `http://127.0.0.1:${(server.address() as AddressInfo).port}`,
        requests,
        pathsHit: (prefix: string) => requests.filter((r) => r.url.startsWith(prefix)),
        setAuthStatus: (status: number) => {
          authStatus = status;
        },
        setTelemetryStatus: (status: number) => {
          telemetryStatus = status;
        },
        close: () => new Promise<void>((done) => server.close(() => done())),
      });
    });
  });
}

/** What the child process reports back over stdout. */
interface ChildOutcome {
  state: AuthInfo;
  events: SdkEvent[];
}

/**
 * Bring the SDK up in a fresh process and report what auth ended up as. A real
 * restart is the only way to tell a persisted token from a remembered one.
 *
 * The `-e` payload stays a plain-JS string on purpose: it is source text handed
 * to another `node`, not a module this project compiles.
 */
function runInFreshProcess({
  baseDir,
  baseUrl,
  apiKey,
  flushTelemetry,
}: {
  baseDir: string;
  baseUrl?: string;
  apiKey?: string;
  flushTelemetry?: boolean;
}): Promise<ChildOutcome> {
  const script = `
    const { createRunAnywhere, NativeBackend } = require(${JSON.stringify(DIST)});
    const { addon } = require(${JSON.stringify(path.join(DIST, 'bridge'))});
    (async () => {
      const sdk = createRunAnywhere(new NativeBackend(addon));
      const events = [];
      (async () => { for await (const e of sdk.events) events.push(e); })();
      await sdk.initialize({
        environment: 'production',
        apiKey: ${JSON.stringify(apiKey ?? '')},
        baseUrl: ${JSON.stringify(baseUrl ?? '')},
        baseDir: ${JSON.stringify(baseDir)},
      });
      if (${flushTelemetry ? 'true' : 'false'}) await sdk.telemetry.flush();
      const state = await sdk.auth.state();
      await sdk.reset();
      process.stdout.write('@@' + JSON.stringify({ state, events }) + '@@');
    })().catch((error) => {
      process.stderr.write(String(error && error.stack ? error.stack : error));
      process.exit(1);
    });
  `;
  return new Promise((resolve, reject) => {
    execFile(
      process.execPath,
      ['-e', script],
      { env: { ...process.env, RUNANYWHERE_NATIVE_PATH: NATIVE_PATH }, timeout: 120000 },
      (error, stdout, stderr) => {
        if (error) return reject(new Error(`${error.message}\n${stderr}`));
        const match = /@@(.*)@@/s.exec(stdout);
        if (!match) return reject(new Error(`child produced no result:\n${stdout}\n${stderr}`));
        resolve(JSON.parse(match[1]) as ChildOutcome);
      }
    );
  });
}

function freshBaseDir(name: string): string {
  const dir = path.join(os.tmpdir(), `ra-f3b-${name}-${process.pid}`);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

test('no credentials: the SDK is fully usable and says so', { timeout: 180000, ...SKIP },
  async () => {
    clearCatalog();
    registerCatalog({
      'smollm2-135m': {
        type: 'llm',
        files: [{ url: 'https://example.invalid/smollm2-135m.gguf', as: 'model.gguf' }],
        primary: 'model.gguf',
        label: 'SmolLM2 135M',
        sizeMB: 100,
      },
    });

    const sdk = createRunAnywhere(new NativeBackend(nativeAddon()));
    await sdk.initialize({ environment: 'production' });

    const state = await sdk.auth.state();
    assert.equal(state.status, 'disabled', 'no apiKey means there is nothing to authenticate');
    assert.equal(state.authenticated, false);
    assert.equal(state.deviceRegistered, false);

    // The point of "offline stays usable": local work still runs.
    assert.equal(sdk.isReady, true);
    assert.ok(Array.isArray(await sdk.models.list()));
    if (exists(MODEL_FILE)) {
      const loaded = await sdk.models.load('smollm2-135m');
      assert.equal(loaded.id, 'smollm2-135m');
      const result = await sdk.llm.generate('Say hi.', { maxOutputTokens: 32 });
      assert.ok(result.text.length > 0, 'generation works with no control plane');
    }

    // Nothing to retry, and asking must not throw.
    assert.equal((await sdk.auth.retry()).status, 'disabled');
    await sdk.reset();
    clearCatalog();
  }
);

test('handshake: authenticate, register the device, and POST telemetry with a bearer token',
  { timeout: 180000, ...SKIP },
  async () => {
    const server = await startControlPlane();
    try {
      const result = await runInFreshProcess({
        baseDir: freshBaseDir('handshake'),
        baseUrl: server.baseUrl,
        apiKey: API_KEY,
        flushTelemetry: true,
      });

      assert.equal(result.state.status, 'authenticated', JSON.stringify(result.state));
      assert.equal(result.state.authenticated, true);
      assert.equal(result.state.organizationId, ORG_ID, 'the org id came from the response');
      assert.ok(result.state.expiresAtUnixSec > Date.now() / 1000, 'the token has a live expiry');
      assert.equal(result.state.deviceRegistered, true);
      assert.ok(
        !result.events.some((e) => e.type === 'authFailed'),
        'an authenticated run reports no auth failure'
      );

      const auth = server.pathsHit('/api/v1/auth/sdk/authenticate');
      assert.equal(auth.length, 1, 'the API key was exchanged for a JWT exactly once');
      assert.equal(auth[0].headers.apikey, API_KEY, 'the api key rode the apikey header');
      assert.ok(auth[0].headers['x-platform'], 'the platform header is set');

      const register = server.pathsHit('/api/v1/devices/register');
      assert.equal(register.length, 1, 'the device registered');
      assert.equal(register[0].headers.authorization, 'Bearer access-token-1');
      const payload = JSON.parse(register[0].body) as {
        device_info?: Record<string, unknown>;
      } & Record<string, unknown>;
      const info = payload.device_info ?? payload;
      assert.equal(info.platform, process.platform === 'darwin' ? 'macos' : 'linux');
      assert.ok(String(info.device_model ?? '').length > 0, 'the hardware model was probed');
      assert.ok(Number(info.total_memory ?? 0) > 0, 'RAM came from the platform adapter');

      const telemetry = server.pathsHit('/api/v2/sdk/telemetry/');
      assert.ok(telemetry.length > 0, 'telemetry batches reached the backend');
      assert.equal(telemetry[0].headers.authorization, 'Bearer access-token-1');
      const batch = JSON.parse(telemetry[0].body) as {
        events?: unknown[];
        telemetry?: unknown[];
      };
      const events = batch.events ?? batch.telemetry ?? [];
      assert.ok(events.length > 0, 'the batch carries events');
    } finally {
      await server.close();
    }
  }
);

test('a stored token survives a process restart instead of re-authenticating',
  { timeout: 180000, ...SKIP },
  async () => {
    const server = await startControlPlane();
    const baseDir = freshBaseDir('restart');
    try {
      const first = await runInFreshProcess({ baseDir, baseUrl: server.baseUrl, apiKey: API_KEY });
      assert.equal(first.state.authenticated, true);
      assert.equal(server.pathsHit('/api/v1/auth/sdk/authenticate').length, 1);

      // The second process gets no help from the backend: if the token does not
      // come back out of the secure store, this run cannot be authenticated.
      server.setAuthStatus(500);
      const second = await runInFreshProcess({ baseDir, baseUrl: server.baseUrl, apiKey: API_KEY });
      assert.equal(second.state.authenticated, true, 'the persisted token was restored');
      assert.equal(second.state.status, 'authenticated');
      assert.equal(second.state.organizationId, ORG_ID, 'the org id persisted too');
      assert.equal(
        server.pathsHit('/api/v1/auth/sdk/authenticate').length,
        1,
        'a valid stored token means no second handshake'
      );
    } finally {
      await server.close();
    }
  }
);

test('a near-expiry token refreshes without the caller seeing a failure',
  { timeout: 180000, ...SKIP },
  async () => {
    // 30 seconds is inside commons' 60-second refresh window, so the next run
    // must refresh rather than reuse.
    const server = await startControlPlane({ expiresIn: 30 });
    const baseDir = freshBaseDir('refresh');
    try {
      const first = await runInFreshProcess({ baseDir, baseUrl: server.baseUrl, apiKey: API_KEY });
      assert.equal(first.state.authenticated, true);
      assert.equal(first.state.needsRefresh, true, 'a 30s token is already inside the window');

      const second = await runInFreshProcess({ baseDir, baseUrl: server.baseUrl, apiKey: API_KEY });
      assert.equal(second.state.authenticated, true, 'the refresh kept the run authenticated');
      assert.equal(second.state.status, 'authenticated');
      assert.equal(
        server.pathsHit('/api/v1/auth/sdk/refresh').length,
        1,
        'the refresh token was exchanged'
      );
    } finally {
      await server.close();
    }
  }
);

test('an offline start is reported, not swallowed, and recovers on retry',
  { timeout: 180000, ...SKIP },
  async () => {
    // Claim a port, then close it: the base URL is well-formed and nothing is
    // listening, which is what "offline" looks like to libcurl. The same port
    // comes back up below, so retry has something to reach.
    const probe = await startControlPlane();
    const deadUrl = probe.baseUrl;
    const port = Number(new URL(deadUrl).port);
    await probe.close();

    const sdk = createRunAnywhere(new NativeBackend(nativeAddon()));
    const events: SdkEvent[] = [];
    void (async () => {
      for await (const event of sdk.events) events.push(event);
    })();

    await sdk.initialize({
      environment: 'production',
      apiKey: API_KEY,
      baseUrl: deadUrl,
      baseDir: freshBaseDir('recover'),
    });

    const offline = await sdk.auth.state();
    assert.equal(offline.status, 'offline', JSON.stringify(offline));
    assert.equal(offline.authenticated, false);
    assert.equal(sdk.isReady, true, 'the SDK came up anyway');
    const failure = events.find((e) => e.type === 'authFailed');
    assert.ok(failure, 'the offline start was reported as an event');
    assert.equal(failure.status, 'offline');

    // The network comes back. Retry is the documented recovery, and it must not
    // need a re-initialize.
    const server = await startControlPlane({ port });
    try {
      const recovered = await sdk.auth.retry();
      assert.equal(recovered.status, 'authenticated', JSON.stringify(recovered));
      assert.equal(recovered.authenticated, true);
      assert.equal(
        server.pathsHit('/api/v1/auth/sdk/authenticate').length,
        1,
        'retry ran the handshake the offline start could not'
      );
    } finally {
      await sdk.reset();
      await server.close();
    }
  }
);
