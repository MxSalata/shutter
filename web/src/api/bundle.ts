import { ApiError } from '@/lib/errors';
import { API_BASE, seg } from './client';
import { transport } from './transport';

/**
 * Asks for a case's bundle (CONTRACTS 5) and returns its text as the server wrote it: `request()` parses an answer, and
 * the file's first line, the statement that it is redacted, has to reach the disk as it came.
 */
export async function fetchCaseBundle(caseId: string): Promise<{ text: string; filename: string }> {
  const text = await post(`/cases/${seg(caseId)}/bundle`, '{"redaction":"REDACTED');
  return { text, filename: `shutter-case-${caseId}-redacted.json` };
}

/** The same file unredacted, an approver's, with the reason that goes on the case. Its first line says what it holds. */
export async function fetchUnredactedCaseBundle(
  caseId: string,
  reason: string,
): Promise<{ text: string; filename: string }> {
  const text = await post(`/cases/${seg(caseId)}/bundle-unredacted`, '{"redaction":"UNREDACTED', { reason });
  return { text, filename: `shutter-case-${caseId}-UNREDACTED.json` };
}

async function post(path: string, statement: string, body?: unknown): Promise<string> {
  const req = new Request(new URL(API_BASE + path, window.location.origin), {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'X-Requested-With': 'Shutter',
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    credentials: 'same-origin',
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  let response: Response;
  try {
    response = await transport()(req);
  } catch (e) {
    throw new ApiError({ status: 0, method: 'POST', path, body: e instanceof Error ? e.message : String(e) });
  }
  const text = await response.text();
  if (!response.ok) {
    let body: unknown = text;
    try {
      body = JSON.parse(text);
    } catch {
      // A page that isn't the API's: ApiError reduces it to one line.
    }
    throw new ApiError({ status: response.status, method: 'POST', path, body });
  }
  // A 2xx that doesn't open with the statement is a gate's or a proxy's page, not a bundle: it is never saved as one.
  if (!text.startsWith(statement)) {
    throw new ApiError({ status: 502, method: 'POST', path, body: text });
  }
  return text;
}

/** Hands text to the browser as a file to save. */
export function saveTextFile(text: string, filename: string): void {
  const url = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.append(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
