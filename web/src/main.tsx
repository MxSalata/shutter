import '@mantine/core/styles.css';
import '@mantine/notifications/styles.css';
import './styles.css';

import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import { DEMO_BUILD, TRIAL } from './env/mode';

async function bootstrap() {
  // The trial: the demo build, and development against recorded data. The in-browser mock of the REST API starts
  // before the first request (its service worker, which only the demo build carries).
  if (DEMO_BUILD && TRIAL) {
    const { startMock } = await import('./mocks/browser');
    await startMock();
  }
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}

void bootstrap();
