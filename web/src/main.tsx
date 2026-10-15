import '@mantine/core/styles.css';
import '@mantine/notifications/styles.css';
import './styles.css';

import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';

async function bootstrap() {
  // Development against recorded data: the in-browser mock of the REST API starts before the first request.
  if (import.meta.env.VITE_MOCK === '1') {
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
