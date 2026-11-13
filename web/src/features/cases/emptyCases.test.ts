import { describe, expect, it } from 'vitest';
import type { Health } from '@/api/types';
import { emptyGuidance, emptyInstall, forwardingNamespaces, siteProduction } from './emptyCases';
import {
  DEMO_INSTALL,
  SITE_AWAITING_SETUP,
  SITE_IN_ITS_OWN_PRODUCTION,
  SITE_WITH_INTAKE,
  SITE_WITH_NOTHING_FORWARDING,
  SITE_WITH_TROUBLED_INTAKE,
} from './emptyCases.fixtures';

const all = { scenarios: true, configure: true };
const operator = { scenarios: true, configure: false };
const lookOnly = { scenarios: false, configure: false };

describe('emptyInstall', () => {
  it('is the trial whatever the report says, since the trial answers in the browser', () => {
    expect(emptyInstall(true, undefined)).toBe('trial');
    expect(emptyInstall(true, SITE_AWAITING_SETUP)).toBe('trial');
  });

  it("reads a demo from the report's own demo field", () => {
    expect(emptyInstall(false, DEMO_INSTALL)).toBe('demo');
  });

  it('tells a site that has an intake from one that has none yet', () => {
    expect(emptyInstall(false, SITE_WITH_INTAKE)).toBe('site-intake');
    expect(emptyInstall(false, SITE_WITH_TROUBLED_INTAKE)).toBe('site-intake');
    expect(emptyInstall(false, SITE_AWAITING_SETUP)).toBe('site-setup');
  });

  it('counts as an intake only a namespace onboarded here, not taken off, with its forwarder', () => {
    expect(forwardingNamespaces(SITE_WITH_NOTHING_FORWARDING)).toEqual([]);
    expect(emptyInstall(false, SITE_WITH_NOTHING_FORWARDING)).toBe('site-setup');
    expect(forwardingNamespaces(SITE_WITH_INTAKE)).toEqual([
      { namespace: 'PATHOLOGY', ok: true },
      { namespace: 'DOCUMENTS', ok: true },
    ]);
  });

  it('guesses nothing when the report is unread or does not say', () => {
    expect(emptyInstall(false, undefined)).toBe('unknown');
    // An answer with no demo field: not a demo and not a site, as far as anyone can tell
    expect(emptyInstall(false, { production_state: 'running' })).toBe('unknown');
    // A site whose server sends no list of watched namespaces (before v1.42): its intake is not known
    expect(emptyInstall(false, { demo: false })).toBe('unknown');
    expect(forwardingNamespaces({ demo: false })).toBeNull();
  });

  it("tells a site whose own production holds Shutter's items (shape B) from one awaiting set-up", () => {
    expect(siteProduction(SITE_IN_ITS_OWN_PRODUCTION)).toBe('Trust.Production');
    expect(emptyInstall(false, SITE_IN_ITS_OWN_PRODUCTION)).toBe('site-production');
    // Shutter's own production, or a report that names none, is not shape B
    expect(siteProduction({ ...SITE_AWAITING_SETUP, shutter_production: 'Shutter.Production' })).toBeNull();
    expect(emptyInstall(false, { ...SITE_AWAITING_SETUP, shutter_production: 'Shutter.Production' })).toBe(
      'site-setup',
    );
    expect(siteProduction({ ...SITE_AWAITING_SETUP, shutter_production: '' })).toBeNull();
    expect(siteProduction(SITE_AWAITING_SETUP)).toBeNull();
    // A shape B site that also has a namespace forwarding has an intake, and is told so
    expect(
      emptyInstall(false, {
        ...SITE_IN_ITS_OWN_PRODUCTION,
        watched_namespaces: SITE_WITH_INTAKE.watched_namespaces,
      }),
    ).toBe('site-intake');
    // Its production is named even by a server that sends no list of watched namespaces
    const { watched_namespaces: _none, ...older } = SITE_IN_ITS_OWN_PRODUCTION;
    expect(emptyInstall(false, older)).toBe('site-production');
  });

  it('never reads a name: a site whose namespace and production are called Demo is still a site', () => {
    const named: Health = {
      ...SITE_AWAITING_SETUP,
      namespace: 'DEMO',
      production: 'Demo.Production',
      shutter_production: 'Shutter.Production',
    };
    expect(emptyInstall(false, named)).toBe('site-setup');
    // And in shape B, a production called Demo is the site's own, not a demo
    expect(emptyInstall(false, { ...named, shutter_production: 'Demo.Production' })).toBe('site-production');
    // And a demo install is one whatever it is called
    expect(emptyInstall(false, { demo: true, namespace: 'TRUST', production: 'Trust.Production' })).toBe(
      'demo',
    );
  });
});

describe('emptyGuidance', () => {
  const at = (trial: boolean, health: Health | undefined, can = all) => emptyGuidance({ trial, health, can });

  it('offers a recorded scenario in the trial', () => {
    expect(at(true, undefined)).toEqual({
      kind: 'trial',
      words: 'No cases yet. Play a recorded scenario to open one.',
      link: { to: '/scenarios', label: 'Play a scenario' },
    });
  });

  it('offers a scenario on a demo, in the words the list has always used', () => {
    expect(at(false, DEMO_INSTALL)).toEqual({
      kind: 'demo',
      words: 'No cases yet. Play a scenario to open one.',
      link: { to: '/scenarios', label: 'Play a scenario' },
    });
  });

  it('tells someone who may not run a scenario who can, and offers no button they cannot use', () => {
    for (const g of [at(false, DEMO_INSTALL, lookOnly), at(true, undefined, lookOnly)]) {
      expect(g.words).toBe('No cases yet. An operator, approver or judge opens one by playing a scenario.');
      expect(g.link).toEqual({ to: '/scenarios', label: 'See the scenarios' });
    }
  });

  it('says on a site with an intake that nothing has failed yet, names what is watched, and points at Health', () => {
    const g = at(false, SITE_WITH_INTAKE);
    expect(g.kind).toBe('site-intake');
    expect(g.words).toBe('No failed delivery has reached Shutter yet. It watches PATHOLOGY and DOCUMENTS.');
    expect(g.link).toEqual({ to: '/health', label: 'If one was expected, check Health' });
  });

  it('keeps a long list of watched namespaces to one sentence', () => {
    const row = (namespace: string) => ({ namespace, onboarded: true, forwarder: true, ok: true });
    const g = at(false, { demo: false, watched_namespaces: ['PAS', 'LAB', 'RAD', 'ED'].map(row) });
    expect(g.words).toBe('No failed delivery has reached Shutter yet. It watches PAS, LAB and 2 more.');
  });

  it("names the namespace whose intake the report finds a problem with, and the others' silence proves nothing", () => {
    const g = at(false, SITE_WITH_TROUBLED_INTAKE);
    expect(g.kind).toBe('site-intake');
    expect(g.words).toBe(
      'No failed delivery has reached Shutter yet, and Health reports a problem with DOCUMENTS.',
    );
    expect(g.link).toEqual({ to: '/health', label: 'Open Health' });
  });

  it("says where Shutter's items run on a site that put them in its own production, and never sends it to set up a namespace", () => {
    for (const can of [all, operator, lookOnly]) {
      expect(at(false, SITE_IN_ITS_OWN_PRODUCTION, can)).toEqual({
        kind: 'site-production',
        words:
          "No cases yet. Shutter's items run in Trust.Production; a case opens when its HL7 process or a forwarder reports a failed delivery.",
        link: { to: '/health', label: 'If one was expected, check Health' },
      });
    }
  });

  it('names the missing step on a site awaiting set-up, with the page for someone who may configure it', () => {
    expect(at(false, SITE_AWAITING_SETUP, all)).toEqual({
      kind: 'site-setup',
      words: 'No cases yet. No watched namespace reports its failures here.',
      link: { to: '/settings/namespaces', label: 'Set up a watched namespace' },
    });
  });

  it('gives someone who may not configure the site the reason and Health, not the set-up page', () => {
    const g = at(false, SITE_AWAITING_SETUP, operator);
    expect(g.words).toBe(
      'No cases yet. No watched namespace reports its failures here; someone who may configure Shutter sets one up.',
    );
    expect(g.link).toEqual({ to: '/health', label: 'See what Health reports' });
  });

  it('never tells a site to play a scenario or to make a failure', () => {
    for (const health of [
      SITE_WITH_INTAKE,
      SITE_WITH_TROUBLED_INTAKE,
      SITE_IN_ITS_OWN_PRODUCTION,
      SITE_AWAITING_SETUP,
    ])
      for (const can of [all, operator, lookOnly]) {
        const g = at(false, health, can);
        expect(`${g.words} ${g.link.label}`).not.toMatch(/scenario|play/i);
        expect(g.link.to).not.toBe('/scenarios');
      }
  });

  it('says only that there are none when the install has not said what it is', () => {
    expect(at(false, undefined)).toEqual({
      kind: 'unknown',
      words: 'No cases yet.',
      link: { to: '/health', label: 'Open Health' },
    });
  });
});
