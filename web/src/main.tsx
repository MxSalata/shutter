import '@mantine/core/styles.css';
import '@mantine/notifications/styles.css';
import './styles.css';

import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import { chooseTransport, liveTransport } from './api/transport';
import { ENV, TRIAL } from './env/mode';
import { lockNetworkForTrial } from './env/guard';
import { provideTrialChrome } from './trial/slot';
import { TrialFailed } from './trial/TrialFailed';
import { enterTrialPage } from './trial/visit';

const root = () => createRoot(document.getElementById('root')!);

/**
 * Start: the page's environment is fixed here, once. A trial page locks the network first, then loads the recorded
 * mock in its own chunk and answers every call from it; if that fails, the trial says so and never falls back to the
 * live system. A live page sends with `fetch`. Only then does the app render.
 */
async function bootstrap() {
  if (TRIAL) {
    lockNetworkForTrial();
    enterTrialPage();
    try {
      // The recorded mock and the trial's chrome (banner, menus, the guide), in chunks only trial pages load
      const [{ createTrialTransport }, chrome] = await Promise.all([
        import('./trial/transport'),
        import('./trial/chrome'),
      ]);
      chooseTransport(createTrialTransport(ENV.role));
      provideTrialChrome(chrome);
    } catch {
      root().render(<TrialFailed />);
      return;
    }
  } else {
    chooseTransport(liveTransport);
  }
  root().render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}

void bootstrap();
