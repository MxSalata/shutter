/**
 * The words a reader sees on a page's first layer: every visible word in the container outside a closed `TechDetail`
 * (its content stays mounted for text searches, but nobody reads it until it is opened), outside visually hidden text
 * and outside anything marked hidden. The JSON an `ApiSource` shows (its `JsonBlock`) is left out too: it is the
 * machine's own text, shown verbatim for an engineer to copy, not prose a reader reads, so Technical, which opens it,
 * is not charged for it. For the pages' word budget tests: count them in Plain and in Technical, against the page
 * spec's budget (Technical at most 1.5 times Plain).
 */
export function layer1Words(container: HTMLElement): string[] {
  const words: string[] = [];
  const walk = (node: Node) => {
    if (node.nodeType === Node.TEXT_NODE) {
      words.push(...(node.textContent ?? '').split(/\s+/).filter((w) => /[\p{L}\p{N}]/u.test(w)));
      return;
    }
    if (!(node instanceof HTMLElement)) return;
    if (hidden(node)) return;
    for (const child of node.childNodes) walk(child);
  };
  walk(container);
  return words;
}

/** Whether an element's text is out of the first layer: a closed disclosure, the API's JSON, hidden or visually hidden. */
function hidden(el: HTMLElement): boolean {
  if (el.hidden || el.getAttribute('aria-hidden') === 'true') return true;
  if (el.dataset.techDetail === 'closed') return true;
  if (el.classList.contains('json-block')) return true;
  if (el.tagName === 'SCRIPT' || el.tagName === 'STYLE' || el.tagName === 'TEMPLATE') return true;
  // Mantine's VisuallyHidden, and the common sr-only pattern
  if (el.classList.contains('mantine-VisuallyHidden-root') || el.classList.contains('sr-only')) return true;
  const style = el.style;
  return style.display === 'none' || style.visibility === 'hidden';
}

/** The number of first-layer words in the container. */
export const layer1WordCount = (container: HTMLElement) => layer1Words(container).length;
