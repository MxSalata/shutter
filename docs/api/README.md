# The REST API's description

`openapi.json` describes, in OpenAPI 3.1, every route of `src/Shutter/API/Dispatch.cls`'s UrlMap under `/api/shutter`: its method and path, the IRIS resource it checks (`x-required-resource`), whether it changes anything (`x-writes`), whether an `Idempotency-Key` replays it (`x-idempotent`), the section of `docs/CONTRACTS.md` that is its contract (`x-contract`), its parameters, bodies, responses and error codes, and the shapes `web/src/api/types.ts` reads (`components.schemas`). The examples are the recorded demo's (`web/src/mocks/fixtures.json`): synthetic patients, no secrets.

Sign in with `POST /api/shutter/session` (the session cookie then carries the sign-in) or send HTTP Basic credentials on each request. Every change carries `X-Requested-With: Shutter`.

The web application shows the document on its API reference page, under the Detail switch's Technical setting. Any OpenAPI reader (Swagger UI, Redoc, Postman's import) reads the file too.

`scripts/check-openapi.py` fails CI when the document and `Dispatch.cls` disagree: a route without an operation, an operation without a route, or a resource or write flag that does not match the route's own `Allow(...)` call (`Allow()` checks `Shutter_Operate`, and `Allow("")` only a sign-in, so its `x-required-resource` is null). A change to a route changes this file in the same commit. The two forwarded prefixes, `/summaries` and `/assist` (`x-forwarded-prefixes`), are not routes of this class and have no operations here.
