import { useLocation, useMatch } from 'react-router';
import { useMediaQuery } from '@mantine/hooks';
import { pageNameOf } from './screen';

/** The panel's id: the header's button and a case's "Ask about this case" name it in `aria-controls`. */
export const ASSISTANT_PANEL_ID = 'ask-panel';

/** From this width the panel sits beside the page, which keeps its own room; below it the panel is a drawer. */
export const ASSISTANT_WIDE_QUERY = '(min-width: 75em)';

/** What the panel is about: the case on a case page, otherwise the page by its name. */
export type AssistantContext = { kind: 'case'; caseId: string } | { kind: 'page'; page: string };

export const assistantTitle = (ctx: AssistantContext) =>
  ctx.kind === 'case' ? 'Ask about this case' : 'Ask Shutter';

/** The panel's context from the address: a case page's case, or the page's name. */
export function useAssistantContext(): AssistantContext {
  const match = useMatch('/cases/:caseId');
  const { pathname } = useLocation();
  if (match?.params.caseId) return { kind: 'case', caseId: match.params.caseId };
  return { kind: 'page', page: pageNameOf(pathname) };
}

/** Whether the panel sits beside the page (jsdom matches no media query, so a test gets the drawer). */
export const useAssistantWide = () =>
  useMediaQuery(ASSISTANT_WIDE_QUERY, false, { getInitialValueInEffect: false });
