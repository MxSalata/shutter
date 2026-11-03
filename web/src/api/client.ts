import { ApiError } from '@/lib/errors';
import { transport } from './transport';

/** The REST API's base path (CONTRACTS 5). The app is served from the same origin, by IRIS or the Vite proxy. */
export const API_BASE = '/api/shutter';

type Method = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';

export interface RequestOptions {
  body?: unknown;
  /** For the routes the contract marks idempotent: the same key and body replay the first answer. */
  idempotencyKey?: string;
  signal?: AbortSignal;
}

/** A fresh Idempotency-Key: one per action a person takes, reused only if that same action is sent again. */
export function newIdempotencyKey(): string {
  const c: Crypto = globalThis.crypto;
  // randomUUID exists only in secure contexts, and IRIS serves the app over plain http on a LAN: there a version-4
  // UUID is made from getRandomValues, which every context has.
  if (typeof c.randomUUID === 'function') return c.randomUUID();
  const b = c.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = Array.from(b, (x: number) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

export async function request<T>(method: Method, path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (options.body !== undefined) headers['Content-Type'] = 'application/json';
  // The CSRF guard: every change carries it (CONTRACTS 5.1).
  if (method !== 'GET') headers['X-Requested-With'] = 'Shutter';
  if (options.idempotencyKey) headers['Idempotency-Key'] = options.idempotencyKey;
  let response: Response;
  try {
    // The page's transport sends it: fetch in a live page, the recorded mock in the browser in a trial page
    // (api/transport.ts). Everything else about the request is the same in both.
    const req = new Request(new URL(API_BASE + path, window.location.origin), {
      method,
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      credentials: 'same-origin',
      signal: options.signal,
    });
    response = await transport()(req);
  } catch (e) {
    if (e instanceof DOMException && e.name === 'AbortError') throw e;
    if (e instanceof Error && e.name === 'AbortError') throw e;
    throw new ApiError({ status: 0, method, path, body: e instanceof Error ? e.message : String(e) });
  }
  const text = await response.text();
  let data: unknown = null;
  let json = true;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
      json = false;
    }
  }
  if (!response.ok) throw new ApiError({ status: response.status, method, path, body: data });
  // Every API answer is JSON (an empty body is null: a 204). A 2xx with text (a gate's sign-in page, a proxy's
  // maintenance page, answered as 200) is not the API's, and a page reading it as data would fail on it: it is
  // reported as a 502 with the page's title, so the error alert says what came back.
  if (!json) throw new ApiError({ status: 502, method, path, body: data });
  return data as T;
}

export const api = {
  get: <T>(path: string, options?: RequestOptions) => request<T>('GET', path, options),
  post: <T>(path: string, body?: unknown, options?: RequestOptions) =>
    request<T>('POST', path, { ...options, body: body ?? {} }),
  put: <T>(path: string, body: unknown, options?: RequestOptions) =>
    request<T>('PUT', path, { ...options, body }),
  patch: <T>(path: string, body: unknown, options?: RequestOptions) =>
    request<T>('PATCH', path, { ...options, body }),
  del: <T>(path: string, options?: RequestOptions) => request<T>('DELETE', path, options),
};

/** A path segment, encoded. */
export const seg = (value: string) => encodeURIComponent(value);
