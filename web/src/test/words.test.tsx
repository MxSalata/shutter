import { describe, expect, it } from 'vitest';
import { ApiSource } from '@/components/ApiSource';
import { TechDetail } from '@/components/TechDetail';
import { renderUi } from './render';
import { layer1Words } from './words';

function Page() {
  return (
    <div>
      <h1>Health</h1>
      <p>Ready to run cases.</p>
      <span className="mantine-VisuallyHidden-root">read by screen readers only</span>
      <TechDetail label="Reason codes" kind="data">
        <p>NOT_CONFIGURED and four more codes</p>
      </TechDetail>
      <ApiSource endpoint="GET /api/shutter/health" data={{ ready: true, checks: ['iris', 'production'] }} />
    </div>
  );
}

describe('the first layer of a page', () => {
  it("counts the visible words outside closed disclosures, in Plain and in Technical, and never the API's JSON", () => {
    const plain = renderUi(<Page />);
    expect(layer1Words(plain.container)).toEqual([
      'Health',
      'Ready',
      'to',
      'run',
      'cases.',
      'Reason',
      'codes',
      'As',
      'the',
      'API',
      'sends',
      'it',
    ]);
    plain.unmount();
    // Open in Technical: the codes' line, and the API source's endpoint and button, but not its JSON
    const technical = renderUi(<Page />, { detail: 'technical' });
    expect(layer1Words(technical.container).slice(7)).toEqual([
      'NOT_CONFIGURED',
      'and',
      'four',
      'more',
      'codes',
      'As',
      'the',
      'API',
      'sends',
      'it',
      'From',
      'GET',
      '/api/shutter/health',
      'Copy',
      'as',
      'JSON',
    ]);
  });
});
