/**
 * Links to a message's page in the Management Portal (EnsPortal.MessageContents.zen). The page opens the header by the
 * class its link names: with no HeaderClass it answers "ERROR #5809: Object to Load not found, class ''" for any id.
 * So every link the app shows names Ens.MessageHeader, the class of a production's message headers: the links built
 * here, and a link that arrives without the class (a `messageLink` from an API or a recording made before 1.4.5).
 */

const PAGE = 'EnsPortal.MessageContents.zen';
const HEADER_CLASS = 'HeaderClass=Ens.MessageHeader';

/**
 * The Management Portal's page of one message, by its header id, under the portal's base path
 * ("/csp/healthshare/shutter/"). Every page that links to a message builds its link here.
 */
export function messageContentsLink(base: string, headerId: string | number): string {
  return `${base}${PAGE}?${HEADER_CLASS}&HeaderId=${encodeURIComponent(String(headerId))}`;
}

/**
 * A link as it arrived, with the header class added when it opens a message's page and names none. A link that names
 * one already, and a link to any other page, is returned as it came.
 */
export function withHeaderClass(href: string): string {
  const at = href.indexOf(`${PAGE}?`);
  if (at < 0) return href;
  const query = at + PAGE.length + 1;
  if (/(^|&)HeaderClass=/.test(href.slice(query))) return href;
  return `${href.slice(0, query)}${HEADER_CLASS}&${href.slice(query)}`;
}

/**
 * The page of an agent run's message: the link the API sent with the run, with its header class, else one built from
 * the portal's base path and the run's message.
 */
export function runMessageLink(
  run: { messageLink?: string | null; ensMessageId: string | number },
  portalBase: string,
): string {
  return run.messageLink
    ? withHeaderClass(run.messageLink)
    : messageContentsLink(portalBase, run.ensMessageId);
}
