/**
 * The REST API's errors (CONTRACTS 5.1): `{"error": "<code>", "detail": "<text>"}` with 400, 401, 403, 404, 409 or
 * 500. A body that isn't JSON (the web gateway's HTML page, a proxy's error) is reduced to one readable line.
 */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly detail: string;
  readonly method: string;
  readonly path: string;
  readonly body: unknown;

  constructor(init: { status: number; method: string; path: string; body: unknown }) {
    const { code, detail } = readBody(init.body);
    super(detail || code || httpStatusText(init.status));
    this.name = 'ApiError';
    this.status = init.status;
    this.code = code;
    this.detail = detail;
    this.method = init.method;
    this.path = init.path;
    this.body = init.body;
  }

  get isUnauthorized() {
    return this.status === 401;
  }
  get isForbidden() {
    return this.status === 403;
  }
  get isNotFound() {
    return this.status === 404;
  }
  /** 409: the case moved on, the plan changed, or a key was reused. */
  get isConflict() {
    return this.status === 409;
  }
}

function readBody(body: unknown): { code: string; detail: string } {
  if (body && typeof body === 'object') {
    const o = body as Record<string, unknown>;
    return {
      code: typeof o.error === 'string' ? o.error : '',
      detail: typeof o.detail === 'string' ? o.detail : '',
    };
  }
  if (typeof body === 'string') return { code: '', detail: textFromBody(body) };
  return { code: '', detail: '' };
}

export function httpStatusText(status: number): string {
  switch (status) {
    case 0:
      return 'The server could not be reached';
    case 400:
      return 'Bad request';
    case 401:
      return 'Not signed in';
    case 403:
      return 'Your role does not allow this';
    case 404:
      return 'Not found';
    case 409:
      return 'Conflict: something changed meanwhile';
    case 429:
      return 'Too many requests at once: wait a few seconds, then try again';
    case 500:
      return 'Internal server error';
    case 502:
      return 'The answer did not come from the API';
    case 503:
      return 'Shutter is unavailable for a moment, perhaps updating: try again shortly';
    default:
      return `HTTP ${status}`;
  }
}

const MAX_TEXT = 300;

/** A non-JSON error body as one line: an HTML page's title, or its text without the markup. */
export function textFromBody(body: string): string {
  let text = body.trim();
  if (/^<(!doctype|html|head|body|\?xml)/i.test(text)) {
    const title = /<title[^>]*>([^<]*)<\/title>/i.exec(text)?.[1]?.trim();
    text =
      title ||
      text
        .replace(/<(script|style)[\s\S]*?<\/\1>/gi, ' ')
        .replace(/<[^>]+>/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
  }
  return text.length > MAX_TEXT ? `${text.slice(0, MAX_TEXT - 1)}…` : text;
}

export function isApiError(e: unknown): e is ApiError {
  return e instanceof ApiError;
}

/** The scenario player's refusal while a run is queued or playing (Shutter.API.Dispatch): "a run of S3 is still playing". */
const RUN_IN_THE_WAY = /^a run of \S+ is (still playing|queued)$/i;

/**
 * A change whose answer never reached the page: no HTTP answer at all (the connection dropped, the server went away
 * mid-request), or a gateway's or proxy's page where the API's answer should be (a 502, 503 or 504 with no API error
 * code). The server may have recorded the change or not, and the page cannot tell which. A read is never one: nothing
 * was asked to change.
 */
export function answerLost(e: unknown): boolean {
  if (!(e instanceof ApiError) || e.method === 'GET') return false;
  if (e.status === 0) return true;
  return [502, 503, 504].includes(e.status) && !e.code;
}

/** A one-line description of anything thrown. */
export function describeError(e: unknown): string {
  if (e instanceof ApiError) {
    // A rate limit's page (a proxy's, worded for its owner) and a 503 with no word of its own: said for the reader
    if (e.status === 429 || (e.status === 503 && !e.detail)) return httpStatusText(e.status);
    // The run in the way may be anyone's: who to wait for, without the code
    if (e.code === 'wrong_state' && RUN_IN_THE_WAY.test(e.detail))
      return `${e.detail.charAt(0).toUpperCase()}${e.detail.slice(1)}; perhaps another user's, or the hospital's. Try again when it ends.`;
    const what = e.detail || httpStatusText(e.status);
    return e.code && !what.includes(e.code) ? `${what} (${e.code})` : what;
  }
  if (e instanceof Error) return e.message;
  if (typeof e === 'string') return e;
  return 'Unknown error';
}
