import { http, HttpResponse, type JsonBodyType } from 'msw';
import recorded from './onboarding.json';

/**
 * The trial's answers for the Settings screen's watched namespaces (CONTRACTS 11.1): what the real routes answered on a
 * stock instance (tests/e2e/onboard_api_check.py --record). An apply replays the recorded apply, with the plan's digest
 * checked as the server checks it, and the namespace then reads as onboarded until the mock starts again. Only the plain
 * plan was recorded, so options are refused rather than answered wrongly.
 */
const BASE = '/api/shutter/settings/namespaces';
interface Recorded {
  plan: { digest: string };
  planAfter: { digest: string };
  apply: JsonBodyType;
  test: JsonBodyType;
  testNoCredential: JsonBodyType;
  watched: JsonBodyType;
  removal: JsonBodyType;
  remove: JsonBodyType;
}
const namespaces = recorded.namespaces as unknown as Record<string, Recorded>;
let on = new Set<string>();

export function resetOnboarding() {
  on = new Set();
}

export function onboardingHandlers(
  csrf: (request: Request) => Response | null,
  guard: (need: 'configure') => Response | null,
) {
  const refuse = (request?: Request) => (request ? csrf(request) : null) ?? guard('configure');
  const unknown = (ns: string) =>
    HttpResponse.json(
      { error: 'not_found', detail: `The trial has no recording for ${ns}` },
      { status: 404 },
    );
  return [
    http.get(BASE, () => {
      const denied = refuse();
      if (denied) return denied;
      const names = Object.keys(namespaces);
      return HttpResponse.json({
        shutterNamespace: 'SHUTTER',
        recordedAt: recorded.recordedAt,
        canApply: true,
        watched: names.filter((n) => on.has(n)).map((n) => namespaces[n].watched),
        available: names.filter((n) => !on.has(n)).map((namespace) => ({ namespace })),
      });
    }),
    http.post(`${BASE}/:ns/plan`, async ({ request, params }) => {
      const denied = refuse(request);
      if (denied) return denied;
      const ns = String(params.ns);
      if (!namespaces[ns]) return unknown(ns);
      const body = (await request.json()) as { options?: Record<string, unknown> };
      if (Object.keys(body.options ?? {}).length)
        return HttpResponse.json(
          { error: 'bad_request', detail: 'The trial replays the plan with no options' },
          { status: 400 },
        );
      return HttpResponse.json(on.has(ns) ? namespaces[ns].planAfter : namespaces[ns].plan);
    }),
    http.post(`${BASE}/:ns/apply`, async ({ request, params }) => {
      const denied = refuse(request);
      if (denied) return denied;
      const ns = String(params.ns);
      if (!namespaces[ns]) return unknown(ns);
      const body = (await request.json()) as { digest?: string };
      const current = on.has(ns) ? namespaces[ns].planAfter : namespaces[ns].plan;
      if (body.digest !== current.digest)
        return HttpResponse.json(
          { error: 'plan_changed', detail: 'The plan has changed since it was read', ...current },
          { status: 409 },
        );
      on.add(ns);
      return HttpResponse.json(namespaces[ns].apply);
    }),
    http.post(`${BASE}/:ns/test`, ({ request, params }) => {
      const denied = refuse(request);
      if (denied) return denied;
      const ns = String(params.ns);
      if (!namespaces[ns]) return unknown(ns);
      return HttpResponse.json(on.has(ns) ? namespaces[ns].test : namespaces[ns].testNoCredential);
    }),
    http.get(`${BASE}/:ns/removal`, ({ params }) => {
      const denied = refuse();
      if (denied) return denied;
      const ns = String(params.ns);
      return namespaces[ns] ? HttpResponse.json(namespaces[ns].removal) : unknown(ns);
    }),
    http.post(`${BASE}/:ns/remove`, ({ request, params }) => {
      const denied = refuse(request);
      if (denied) return denied;
      const ns = String(params.ns);
      if (!namespaces[ns]) return unknown(ns);
      on.delete(ns);
      return HttpResponse.json(namespaces[ns].remove);
    }),
  ];
}
