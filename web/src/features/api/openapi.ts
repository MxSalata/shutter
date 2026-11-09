import document from '../../../../docs/api/openapi.json?doc';

/**
 * The REST API's description (docs/api/openapi.json, OpenAPI 3.1), read at build time: every route of
 * src/Shutter/API/Dispatch.cls's UrlMap with the resource it checks, whether it changes anything, its parameters,
 * bodies and replies, and the shapes web/src/api/types.ts reads. These are the shapes the API reference page uses, the
 * routes as a list and in their groups, the filter, an example built from a shape, and a curl line for a route.
 */
export type Method = 'get' | 'post' | 'put' | 'patch' | 'delete';
export const METHODS: readonly Method[] = ['get', 'post', 'put', 'patch', 'delete'];

export interface Schema {
  $ref?: string;
  type?: string | string[];
  format?: string;
  enum?: unknown[];
  const?: unknown;
  title?: string;
  description?: string;
  properties?: Record<string, Schema>;
  required?: string[];
  items?: Schema;
  additionalProperties?: boolean | Schema;
  allOf?: Schema[];
  oneOf?: Schema[];
  anyOf?: Schema[];
  examples?: unknown[];
  example?: unknown;
  default?: unknown;
  minimum?: number;
  maximum?: number;
  maxLength?: number;
  pattern?: string;
}

export interface Parameter {
  $ref?: string;
  name: string;
  in: 'path' | 'query' | 'header' | 'cookie';
  required?: boolean;
  description?: string;
  schema?: Schema;
  example?: unknown;
}

export interface Media {
  schema?: Schema;
  example?: unknown;
  examples?: Record<string, { value?: unknown; summary?: string }>;
}

export interface RequestBody {
  required?: boolean;
  description?: string;
  content?: Record<string, Media>;
}

export interface Response {
  description?: string;
  content?: Record<string, Media>;
  'x-error-codes'?: string[];
}

export interface Operation {
  operationId?: string;
  tags?: string[];
  summary?: string;
  description?: string;
  parameters?: Parameter[];
  requestBody?: RequestBody;
  responses: Record<string, Response>;
  /** The section of docs/CONTRACTS.md that is the route's contract. */
  'x-contract'?: string;
  /** The IRIS resource the route checks (two when it checks a second one on the way), null when it checks none. */
  'x-required-resource'?: string | string[] | null;
  /** Whether the route changes anything: then it needs the CSRF header. */
  'x-writes'?: boolean;
  /** Whether an Idempotency-Key replays the first reply. */
  'x-idempotent'?: boolean;
  /** The ObjectScript method that serves it. */
  'x-dispatch'?: string;
  /** The ways in, when they differ from the document's: an empty entry means it answers with no sign-in. */
  security?: Record<string, string[]>[];
}

export interface Tag {
  name: string;
  description?: string;
}

export interface SecurityScheme {
  type: string;
  scheme?: string;
  in?: string;
  name?: string;
  description?: string;
}

export interface Forwarded {
  prefix: string;
  class: string;
  note?: string;
}

export interface ApiDocument {
  openapi: string;
  info: { title: string; version: string; summary?: string; description?: string };
  tags?: Tag[];
  /** The ways in every operation takes unless it names its own. */
  security?: Record<string, string[]>[];
  paths: Record<string, Partial<Record<Method, Operation>> & { parameters?: Parameter[] }>;
  components?: {
    schemas?: Record<string, Schema>;
    parameters?: Record<string, Parameter>;
    securitySchemes?: Record<string, SecurityScheme>;
  };
  'x-forwarded-prefixes'?: Forwarded[];
}

/** The document, as the build read it from docs/api/openapi.json. */
export const API: ApiDocument = document;

/** The base path every route is under. */
export const BASE_PATH = '/api/shutter';

/** One route: an operation with its method and path, and the facts the list shows read once. */
export interface Route {
  /** The operation's id, or its method and path when it has none. */
  id: string;
  method: Method;
  path: string;
  tag: string;
  op: Operation;
  /** The resources it checks, in the order the document names them. */
  resources: string[];
  writes: boolean;
  idempotent: boolean;
  /** It answers before anyone signs in (its security lists an empty entry); otherwise a sign-in comes first. */
  open: boolean;
  /** The path's and the operation's parameters, each resolved from the document's components. */
  parameters: Parameter[];
}

/** The name a `#/components/<kind>/<name>` reference points at. */
export const refName = (ref: string): string => ref.split('/').pop() ?? ref;

/** What a `#/components/...` reference points at, or undefined. */
export function resolve<T>(ref: string, doc: ApiDocument = API): T | undefined {
  const m = /^#\/components\/(\w+)\/(.+)$/.exec(ref);
  if (!m) return undefined;
  const kind = doc.components?.[m[1] as keyof NonNullable<ApiDocument['components']>] as
    Record<string, unknown> | undefined;
  return kind?.[m[2]] as T | undefined;
}

/** A parameter with its reference followed. */
export function resolveParameter(p: Parameter, doc: ApiDocument = API): Parameter {
  return p.$ref ? (resolve<Parameter>(p.$ref, doc) ?? p) : p;
}

/** The resources an operation names, as a list. */
function resourcesOf(op: Operation): string[] {
  const r = op['x-required-resource'];
  return Array.isArray(r) ? r : r ? [r] : [];
}

/** Every route of the document, in the document's order (paths, then methods as the document lists them). */
export function routesOf(doc: ApiDocument = API): Route[] {
  const out: Route[] = [];
  for (const [path, item] of Object.entries(doc.paths)) {
    for (const method of Object.keys(item) as (Method | 'parameters')[]) {
      if (method === 'parameters' || !METHODS.includes(method)) continue;
      const op = item[method];
      if (!op) continue;
      out.push({
        id: op.operationId ?? `${method} ${path}`,
        method,
        path,
        tag: op.tags?.[0] ?? 'other',
        op,
        resources: resourcesOf(op),
        writes: op['x-writes'] === true,
        idempotent: op['x-idempotent'] === true,
        open: (op.security ?? doc.security ?? []).some((s) => Object.keys(s).length === 0),
        parameters: [...(item.parameters ?? []), ...(op.parameters ?? [])].map((p) =>
          resolveParameter(p, doc),
        ),
      });
    }
  }
  return out;
}

/** The routes of one tag, in the document's order of tags; a tag the document does not declare comes last. */
export interface RouteGroup {
  tag: string;
  description?: string;
  routes: Route[];
}

export function groupsOf(routes: Route[], doc: ApiDocument = API): RouteGroup[] {
  const declared = doc.tags ?? [];
  const order = new Map(declared.map((t, i) => [t.name, i]));
  const byTag = new Map<string, Route[]>();
  for (const r of routes) byTag.set(r.tag, [...(byTag.get(r.tag) ?? []), r]);
  return [...byTag.entries()]
    .sort(
      ([a], [b]) =>
        (order.get(a) ?? declared.length) - (order.get(b) ?? declared.length) || a.localeCompare(b),
    )
    .map(([tag, rs]) => ({
      tag,
      description: declared.find((t) => t.name === tag)?.description,
      routes: rs,
    }));
}

/** A tag's name as a heading: "site profile" becomes "Site profile". */
export const tagLabel = (tag: string): string => tag.charAt(0).toUpperCase() + tag.slice(1);

/** The resources the routes check, each once, in alphabetical order. */
export const allResources = (routes: Route[]): string[] =>
  [...new Set(routes.flatMap((r) => r.resources))].sort((a, b) => a.localeCompare(b));

/** The reads, the changes, or every route. */
export type Kind = 'all' | 'reads' | 'changes';

export interface Filter {
  /** Words to find in the method, the path, the operation's id, its tag or its summary; case does not matter. */
  query: string;
  kind: Kind;
  /** One resource the route must check, or '' for any. */
  resource: string;
}

export const NO_FILTER: Filter = { query: '', kind: 'all', resource: '' };

/** Whether a route is one the words name: every word must occur in its method, path, id, tag, summary or resources. */
export function matches(route: Route, query: string): boolean {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (!words.length) return true;
  const text = [route.method, route.path, route.id, route.tag, route.op.summary ?? '', ...route.resources]
    .join(' ')
    .toLowerCase();
  return words.every((w) => text.includes(w));
}

export function filterRoutes(routes: Route[], filter: Filter): Route[] {
  return routes.filter(
    (r) =>
      matches(r, filter.query) &&
      (filter.kind === 'all' || (filter.kind === 'changes') === r.writes) &&
      (!filter.resource || r.resources.includes(filter.resource)),
  );
}

/** The JSON media of a body or a reply, when it has one. */
export const jsonMedia = (content?: Record<string, Media>): Media | undefined =>
  content?.['application/json'] ?? (content ? Object.values(content)[0] : undefined);

/** A schema with its reference followed, once. */
export function deref(schema: Schema | undefined, doc: ApiDocument = API): Schema | undefined {
  if (!schema) return undefined;
  if (schema.$ref) return resolve<Schema>(schema.$ref, doc) ?? schema;
  // `allOf` with one referenced part is how the document says "this shape, with a description of its own"
  if (schema.allOf?.length === 1 && schema.allOf[0].$ref)
    return { ...deref(schema.allOf[0], doc), ...schema };
  return schema;
}

/** The named shape a schema is, or wraps in `allOf`, when it is one: for a link to that shape. */
export function refOf(schema: Schema | undefined): string | undefined {
  if (!schema) return undefined;
  if (schema.$ref) return refName(schema.$ref);
  if (schema.allOf?.length === 1 && schema.allOf[0].$ref) return refName(schema.allOf[0].$ref);
  return undefined;
}

/** A schema's type in a few words: "string", "array of CaseSummary", "CaseList or array of Scenario", "object". */
export function typeName(schema: Schema | undefined, doc: ApiDocument = API): string {
  if (!schema) return '';
  const ref = refOf(schema);
  if (ref) return ref;
  if (schema.oneOf) return schema.oneOf.map((s) => typeName(s, doc)).join(' or ');
  if (schema.anyOf) return schema.anyOf.map((s) => typeName(s, doc)).join(' or ');
  if (schema.allOf) return schema.allOf.map((s) => typeName(s, doc)).join(' and ');
  if (schema.const !== undefined) return JSON.stringify(schema.const);
  const type = Array.isArray(schema.type) ? schema.type.join(' or ') : schema.type;
  if (type === 'array' || (!type && schema.items))
    return `array of ${typeName(schema.items, doc) || 'anything'}`;
  if (!type) return schema.properties ? 'object' : 'any';
  return schema.format ? `${type} (${schema.format})` : type;
}

/** The values a schema allows, when it lists them (an enum, a constant), following one reference. */
export function choices(schema: Schema | undefined, doc: ApiDocument = API): unknown[] | undefined {
  const s = deref(schema, doc);
  if (!s) return undefined;
  if (s.enum) return s.enum;
  if (s.const !== undefined) return [s.const];
  return undefined;
}

/** The limits a schema states, as short notes: "1 to 500", "default 50", "at most 128 characters", a pattern. */
export function constraints(schema: Schema | undefined): string[] {
  if (!schema) return [];
  const out: string[] = [];
  if (schema.minimum !== undefined && schema.maximum !== undefined)
    out.push(`${schema.minimum} to ${schema.maximum}`);
  else if (schema.minimum !== undefined) out.push(`at least ${schema.minimum}`);
  else if (schema.maximum !== undefined) out.push(`at most ${schema.maximum}`);
  if (schema.maxLength !== undefined) out.push(`at most ${schema.maxLength} characters`);
  if (schema.default !== undefined) out.push(`default ${JSON.stringify(schema.default)}`);
  if (schema.pattern) out.push(`pattern ${schema.pattern}`);
  return out;
}

/**
 * An example of a schema: the one the document gives (the recorded demo's), or one built from the shape: the
 * first of an enum, a constant, a default, and for an object its required fields, or every field when they are few.
 */
export function exampleOf(schema: Schema | undefined, doc: ApiDocument = API, depth = 0): unknown {
  if (!schema || depth > 4) return undefined;
  if (schema.examples?.length) return schema.examples[0];
  if (schema.example !== undefined) return schema.example;
  const s = deref(schema, doc);
  if (!s) return undefined;
  if (s !== schema && (s.examples?.length || s.example !== undefined)) return exampleOf(s, doc, depth);
  if (s.default !== undefined) return s.default;
  if (s.const !== undefined) return s.const;
  if (s.enum?.length) return s.enum[0];
  if (s.oneOf?.length) return exampleOf(s.oneOf[0], doc, depth + 1);
  if (s.anyOf?.length) return exampleOf(s.anyOf[0], doc, depth + 1);
  if (s.allOf?.length)
    return Object.assign({}, ...s.allOf.map((part) => exampleOf(part, doc, depth + 1) ?? {}));
  const type = Array.isArray(s.type) ? s.type[0] : s.type;
  if (type === 'array' || (!type && s.items)) {
    const item = exampleOf(s.items, doc, depth + 1);
    return item === undefined ? [] : [item];
  }
  if (type === 'object' || s.properties) {
    const props = Object.entries(s.properties ?? {});
    const required = new Set(s.required ?? []);
    const shown = props.length <= 12 ? props : props.filter(([k]) => required.has(k));
    return Object.fromEntries(
      shown.map(([k, v]) => [k, exampleOf(v, doc, depth + 1)]).filter(([, v]) => v !== undefined),
    );
  }
  if (type === 'integer' || type === 'number') return 0;
  if (type === 'boolean') return true;
  if (type === 'null') return null;
  if (s.format === 'date-time') return '2026-01-01T00:00:00Z';
  return 'text';
}

/** A path parameter's value for an example: the one the document gives, or the name in angle brackets. */
function pathValue(name: string, route: Route, doc: ApiDocument): string {
  const p = route.parameters.find((q) => q.in === 'path' && q.name === name);
  const value = p?.example ?? exampleOf(p?.schema, doc);
  return typeof value === 'string' && value !== 'text' ? value : `<${name}>`;
}

/**
 * The route as a curl command: `-u <user>` asks for the password rather than putting it in the line, a change carries
 * the CSRF header, an idempotent one a key to fill in, and a body is the example built from its shape.
 */
export function curlFor(route: Route, origin: string, doc: ApiDocument = API): string {
  const url = origin + route.path.replace(/\{(\w+)\}/g, (_, name) => pathValue(name, route, doc));
  const lines = [`curl -u <user>`];
  if (route.method !== 'get') lines.push(`-X ${route.method.toUpperCase()}`);
  if (route.writes) lines.push(`-H 'X-Requested-With: Shutter'`);
  if (route.idempotent) lines.push(`-H 'Idempotency-Key: <one key per action>'`);
  const body = jsonMedia(route.op.requestBody?.content);
  if (body) {
    lines.push(`-H 'Content-Type: application/json'`);
    const example = body.example ?? exampleOf(body.schema, doc) ?? {};
    lines.push(`-d '${JSON.stringify(example).replace(/'/g, `'\\''`)}'`);
  }
  lines.push(`'${url}'`);
  return lines.join(' \\\n  ');
}

/** The first successful reply's code and media, when the operation has one. */
export function successOf(op: Operation): { code: string; response: Response } | undefined {
  const code = Object.keys(op.responses)
    .filter((c) => c.startsWith('2'))
    .sort()[0];
  return code ? { code, response: op.responses[code] } : undefined;
}

/** The first sentence of a description, for a list. */
export const firstSentence = (text: string | undefined): string => (text ?? '').split(/(?<=\.)\s/)[0] ?? '';
