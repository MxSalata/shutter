import { describe, expect, it } from 'vitest';
import {
  allResources,
  API,
  BASE_PATH,
  choices,
  constraints,
  curlFor,
  exampleOf,
  filterRoutes,
  groupsOf,
  matches,
  NO_FILTER,
  routesOf,
  successOf,
  typeName,
  type Route,
} from './openapi';

const routes = routesOf();
const byId = (id: string): Route => {
  const r = routes.find((x) => x.id === id);
  if (!r) throw new Error(`no route ${id}`);
  return r;
};

describe('the API document', () => {
  it('describes every route under the base path, each with one tag, a summary and a success reply', () => {
    expect(routes.length).toBeGreaterThanOrEqual(62);
    expect(new Set(routes.map((r) => r.id)).size).toBe(routes.length);
    for (const r of routes) {
      expect(r.path.startsWith(`${BASE_PATH}/`)).toBe(true);
      expect(r.op.tags).toHaveLength(1);
      expect(r.op.summary).toBeTruthy();
      expect(successOf(r.op)).toBeDefined();
      expect(typeof r.writes).toBe('boolean');
    }
  });

  it('says what each route needs, as the server checks it', () => {
    expect(byId('login').resources).toEqual([]);
    expect(byId('cases').resources).toEqual(['Shutter_Operate']);
    expect(byId('caseApprove').resources).toEqual(['Shutter_Approve']);
    expect(byId('caseBoard').resources).toEqual(['Shutter_Operate', 'Shutter_LiveAgents']);
    expect(byId('caseApprove').writes).toBe(true);
    expect(byId('caseApprove').idempotent).toBe(true);
    expect(byId('cases').writes).toBe(false);
    expect(byId('access').resources).toEqual([]);
    expect(byId('access').writes).toBe(false);
    expect(byId('access').tag).toBe('session');
    // No resource is not the same as open: /me and /access need a sign-in, the session and health routes do not
    expect(byId('access').open).toBe(false);
    expect(byId('me').open).toBe(false);
    expect(byId('login').open).toBe(true);
    expect(byId('health').open).toBe(true);
    expect(byId('cases').open).toBe(false);
    expect(allResources(routes)).toEqual([
      'Shutter_Approve',
      'Shutter_Configure',
      'Shutter_Intake',
      'Shutter_LiveAgents',
      'Shutter_Operate',
      'Shutter_Scenarios',
    ]);
  });

  it('resolves a path parameter declared in the components', () => {
    const approve = byId('caseApprove');
    expect(approve.parameters.map((p) => p.name)).toEqual(['caseId', 'X-Requested-With', 'Idempotency-Key']);
    expect(approve.parameters[1].in).toBe('header');
    expect(approve.parameters[1].description).toMatch(/CSRF/);
  });

  it('groups the routes in the order the document declares its tags, every route in one group', () => {
    const groups = groupsOf(routes);
    expect(groups.map((g) => g.tag)).toEqual((API.tags ?? []).map((t) => t.name));
    expect(groups.flatMap((g) => g.routes)).toHaveLength(routes.length);
    expect(groups.find((g) => g.tag === 'site profile')?.routes.map((r) => r.method)).toEqual([
      'get',
      'put',
      'get',
    ]);
  });
});

describe('the filter', () => {
  it('finds a route by any word of its method, path, id, tag, summary or resource', () => {
    const cases = byId('cases');
    expect(matches(cases, '')).toBe(true);
    expect(matches(cases, 'GET cases')).toBe(true);
    expect(matches(cases, 'shutter_operate')).toBe(true);
    expect(matches(cases, 'incidents')).toBe(false);
    expect(filterRoutes(routes, { ...NO_FILTER, query: 'site-profile' }).map((r) => r.id)).toEqual([
      'siteProfileGet',
      'siteProfilePut',
      'siteProfileHistory',
    ]);
  });

  it('keeps the reads or the changes, and the routes one resource guards', () => {
    const changes = filterRoutes(routes, { ...NO_FILTER, kind: 'changes' });
    const reads = filterRoutes(routes, { ...NO_FILTER, kind: 'reads' });
    expect(changes.every((r) => r.writes)).toBe(true);
    expect(reads.every((r) => !r.writes)).toBe(true);
    expect(changes.length + reads.length).toBe(routes.length);
    const approver = filterRoutes(routes, { ...NO_FILTER, resource: 'Shutter_Approve' });
    expect(approver.map((r) => r.id)).toContain('caseApprove');
    expect(approver.map((r) => r.id)).not.toContain('cases');
  });
});

describe('types and examples', () => {
  it('names a type in a few words', () => {
    expect(typeName({ $ref: '#/components/schemas/CaseSummary' })).toBe('CaseSummary');
    expect(typeName({ type: 'array', items: { $ref: '#/components/schemas/Scenario' } })).toBe(
      'array of Scenario',
    );
    expect(typeName({ allOf: [{ $ref: '#/components/schemas/Mode' }], default: 'board' })).toBe('Mode');
    expect(typeName(API.components?.schemas?.ScenarioListOrArray)).toBe('ScenarioList or array of Scenario');
    expect(typeName({ type: 'string', const: 'Shutter' })).toBe('"Shutter"');
    expect(typeName({ type: ['string', 'null'] })).toBe('string or null');
    expect(choices({ $ref: '#/components/schemas/Mode' })).toContain('board');
    expect(constraints({ type: 'integer', minimum: 1, maximum: 500, default: 50 })).toEqual([
      '1 to 500',
      'default 50',
    ]);
  });

  it('takes the recorded example when the document has one, and builds one from the shape otherwise', () => {
    const summary = exampleOf({ $ref: '#/components/schemas/CaseSummary' }) as Record<string, unknown>;
    expect(summary).toEqual(API.components?.schemas?.CaseSummary.examples?.[0]);
    expect(typeof summary.caseId).toBe('string');
    const decision = exampleOf({ $ref: '#/components/schemas/ApprovalDecision' });
    expect(decision).toEqual({
      decision: 'approve',
      planDigest: 'text',
      expectedVersion: 0,
      comment: 'text',
    });
    const list = exampleOf({ $ref: '#/components/schemas/CaseList' }) as { items: unknown[]; total: number };
    expect(list.items).toHaveLength(1);
    expect(list.total).toBe(0);
  });

  it('writes a curl line that asks for the password, carries the headers a change needs and fills the path', () => {
    const approve = curlFor(byId('caseApprove'), 'http://localhost:52773');
    expect(approve).toContain('curl -u <user>');
    expect(approve).toContain('-X POST');
    expect(approve).toContain("-H 'X-Requested-With: Shutter'");
    expect(approve).toContain("-H 'Idempotency-Key: <one key per action>'");
    expect(approve).toContain('"decision":"approve"');
    expect(approve).toContain("'http://localhost:52773/api/shutter/cases/C-000064/approvals'");
    expect(approve).not.toContain('password');
    const cases = curlFor(byId('cases'), 'https://iris.example');
    expect(cases).toBe("curl -u <user> \\\n  'https://iris.example/api/shutter/cases'");
  });
});
