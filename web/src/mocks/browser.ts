import { setupWorker } from 'msw/browser';
import { handlers, resetMock } from './handlers';

export const worker = setupWorker(...handlers);

/** Starts the mock before the app renders; the first request already hits it. */
export async function startMock() {
  resetMock(null);
  await worker.start({
    serviceWorker: { url: `${import.meta.env.BASE_URL}mockServiceWorker.js` },
    onUnhandledRequest: 'bypass',
    quiet: true,
  });
}
