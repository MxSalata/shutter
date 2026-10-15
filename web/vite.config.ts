/// <reference types="vitest/config" />
import { defineConfig, loadEnv, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath, URL } from 'node:url';
import { readFileSync, rmSync } from 'node:fs';
import { resolve } from 'node:path';

// Interlock's web application - Vite configuration.
//
// Modes:
//   dev    `vite`                     proxies /api/interlock to an IRIS instance (VITE_IRIS_URL)
//   iris   `vite build --mode iris`   ../www/, the build IRIS serves at /interlock/ (npm run build:www)

/**
 * The Content-Security-Policy of the build IRIS serves: scripts only from the app's own files, none inline, and
 * calls only to its own origin.
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
    name: 'interlock-content-security-policy',
    apply: 'build',
    transformIndexHtml: (html) =>
      html.replace(
        '<meta charset="UTF-8" />',
        `$&\n    <meta http-equiv="Content-Security-Policy" content="${policy}" />`,
      ),
  };
}

/** The mock API's service worker (public/, for `VITE_MOCK=1` development) stays out of the build IRIS serves. */
function withoutMockWorker(): Plugin {
  let outDir = '';
  return {
    name: 'interlock-without-mock-worker',
    apply: 'build',
    configResolved(config) {
      outDir = resolve(config.root, config.build.outDir);
    },
    closeBundle() {
      rmSync(resolve(outDir, 'mockServiceWorker.js'), { force: true });
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
    // IRIS serves the build at /interlock/; the dev server at its root.
    base: mode === 'iris' ? '/interlock/' : '/',
    plugins: [react(), ...(mode === 'iris' ? [contentSecurityPolicy(), withoutMockWorker()] : [])],
    define: { __APP_VERSION__: JSON.stringify(version) },
    resolve: {
      alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
    },
    server: {
      port: 5173,
      strictPort: true,
      proxy: {
        // The browser talks to Vite, Vite to IRIS: same origin, so the session cookie works as it will when IRIS
        // serves the app. A Basic challenge on a 401 would open the browser's own login dialog.
        '/api/interlock': {
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
    build: {
      sourcemap: env.VITE_SOURCEMAP === '1',
      rollupOptions: {
        output: {
          manualChunks: {
            react: ['react', 'react-dom', 'react-dom/client', 'react-router'],
            mantine: ['@mantine/core', '@mantine/hooks', '@mantine/notifications', '@mantine/modals'],
            query: ['@tanstack/react-query'],
          },
        },
      },
    },
    test: {
      environment: 'jsdom',
      globals: true,
      setupFiles: ['./src/test/setup.ts'],
      include: ['src/**/*.test.{ts,tsx}'],
      css: false,
    },
  };
});
