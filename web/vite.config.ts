/// <reference types="vitest/config" />
import { defineConfig, loadEnv, searchForWorkspaceRoot, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath, URL } from 'node:url';
import { readFileSync } from 'node:fs';

// Shutter's web application - Vite configuration.
//
// Modes:
//   dev    `vite`                     proxies /api/shutter to an IRIS instance (VITE_IRIS_URL)
//   iris   `vite build --mode iris`   ../www/, the build IRIS serves at /shutter/ (npm run build:www)
//   demo   `vite build --mode demo`   dist-demo/, always the trial (GitHub Pages, the e2e tests)
//
// Every build carries the trial (`?trial` in the address): the recorded mock answers its calls in the browser, from a
// chunk only trial pages load. VITE_BASE sets the demo's base path (GitHub Pages serves /<repo>/); by default it is
// relative. E2E_NO_PROXY=1 turns `vite preview`'s proxy off, so a test of the IRIS build reaches no instance.

/**
 * The Content-Security-Policy of the build IRIS serves and of the demo: scripts only from the app's own files, none
 * inline, and calls only to its own origin. A trial page tightens it further at start (src/env/guard.ts).
 */
function contentSecurityPolicy(): Plugin {
  const policy = [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data:",
    "font-src 'self' data:",
    "connect-src 'self'",
    "base-uri 'none'",
    "form-action 'self'",
  ].join('; ');
  return {
    name: 'shutter-content-security-policy',
    apply: 'build',
    transformIndexHtml: (html) =>
      html.replace(
        '<meta charset="UTF-8" />',
        `$&\n    <meta http-equiv="Content-Security-Policy" content="${policy}" />`,
      ),
  };
}

/**
 * The demo build (and `VITE_MOCK=1` development) is always the trial: its <html> says so, so that
 * public/color-scheme.js marks the page as the trial before the first paint, as `?trial` does on any other build.
 */
function markDemoBuild(): Plugin {
  return {
    name: 'shutter-demo-build',
    transformIndexHtml: (html) =>
      html.replace('<html lang="en-GB">', '<html lang="en-GB" data-shutter-build="demo">'),
  };
}

/**
 * The build's chunks. Shared libraries in their own (React, Mantine, React Query), and the trial's recordings in
 * `trial-data`, apart from the mock's code (`trial`): the recordings change only when they are recorded again, so the
 * committed `www/` does not gain a new 2 MB file on every change to the mock. A JSON file goes to `trial-data` only
 * when nothing but the mock imports it, so no live page ever loads that chunk.
 */
function chunkOf(id: string, getModuleInfo: (id: string) => { importers: readonly string[] } | null) {
  const path = id.replace(/\\/g, '/');
  if (/\/node_modules\/(react|react-dom|react-router|scheduler)\//.test(path)) return 'react';
  if (/\/node_modules\/@mantine\//.test(path)) return 'mantine';
  if (/\/node_modules\/@tanstack\//.test(path)) return 'query';
  if (/\/src\/(mocks\/[^/]+\.ts|trial\/transport\.ts)$/.test(path)) return 'trial';
  if (path.endsWith('.json') && !path.includes('/docs/')) {
    const importers = getModuleInfo(id)?.importers ?? [];
    if (importers.length && importers.every((i) => i.replace(/\\/g, '/').includes('/src/mocks/')))
      return 'trial-data';
  }
  return undefined;
}

/**
 * `docs/readme/evaluation.json?proof`: the slice of the board's evaluation that lib/proof.ts reads (the totals, the
 * sources and each pass's scenario, scoring, entry, cost and played outcome), so a page that shows the proof's figures
 * (sign-in, Scenarios, Settings, the guide) carries a few kilobytes, not the whole document. Vite's own JSON plugin then
 * turns the slice into a module, as it does the whole file for the Evaluation page.
 */
const PROOF_PASS_FIELDS = [
  'scenario',
  'incident',
  'scored',
  'complete',
  'round',
  'rounds',
  'entry_decides',
  'board_disposition',
  'agreement',
  'cost_usd',
  'played',
] as const;
function evaluationProof(): Plugin {
  const suffix = /evaluation\.json\?proof$/;
  return {
    name: 'shutter-evaluation-proof',
    enforce: 'pre',
    load(id) {
      if (!suffix.test(id)) return null;
      const file = id.replace(/\?proof$/, '');
      this.addWatchFile(file);
      const doc = JSON.parse(readFileSync(file, 'utf8')) as {
        sources?: Record<string, unknown>;
        totals?: Record<string, unknown>;
        passes?: Record<string, unknown>[];
      };
      const passes = (doc.passes ?? []).map((p) =>
        Object.fromEntries(PROOF_PASS_FIELDS.filter((k) => k in p).map((k) => [k, p[k]])),
      );
      return JSON.stringify({ sources: doc.sources ?? {}, totals: doc.totals ?? {}, passes });
    },
  };
}

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  const irisUrl = env.VITE_IRIS_URL || 'http://192.168.0.10:52775';
  const { version } = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8')) as {
    version: string;
  };

  return {
    // IRIS serves the build at /shutter/; the demo is relative unless VITE_BASE says otherwise.
    base: mode === 'iris' ? '/shutter/' : mode === 'demo' ? env.VITE_BASE || './' : '/',
    plugins: [
      evaluationProof(),
      react(),
      ...(mode === 'iris' || mode === 'demo' ? [contentSecurityPolicy()] : []),
      ...(mode === 'demo' || env.VITE_MOCK === '1' ? [markDemoBuild()] : []),
    ],
    define: { __APP_VERSION__: JSON.stringify(version) },
    resolve: {
      alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
    },
    server: {
      port: 5173,
      strictPort: true,
      // The mock reads the scenario definitions (fixtures/scenarios.json) beside the recorded answers, and the
      // Evaluation page the board's evaluation (docs/readme/evaluation.json and .md).
      fs: { allow: [searchForWorkspaceRoot(process.cwd()), '../fixtures', '../docs'] },
      proxy: {
        // The browser talks to Vite, Vite to IRIS: same origin, so the session cookie works as it will when IRIS
        // serves the app. A Basic challenge on a 401 would open the browser's own login dialog.
        '/api/shutter': {
          target: irisUrl,
          changeOrigin: true,
          configure: (proxy) => {
            proxy.on('proxyRes', (proxyRes) => {
              delete proxyRes.headers['www-authenticate'];
            });
          },
        },
      },
    },
    // A test of the IRIS build previews it with no proxy (E2E_NO_PROXY=1): otherwise `vite preview` inherits the
    // development proxy to an instance, and a call that escaped the trial would reach it.
    preview: env.E2E_NO_PROXY === '1' ? { proxy: {} } : {},
    build: {
      sourcemap: env.VITE_SOURCEMAP === '1',
      rollupOptions: {
        output: {
          manualChunks: (id, { getModuleInfo }) => chunkOf(id, getModuleInfo),
        },
      },
    },
    test: {
      environment: 'jsdom',
      globals: true,
      setupFiles: ['./src/test/setup.ts'],
      // The self-hosted runner shares a busy host: a page test that walks a dialog can pass 5 s there.
      testTimeout: 30_000,
      include: ['src/**/*.test.{ts,tsx}'],
      css: false,
    },
  };
});
