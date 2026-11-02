/** The package's version (package.json), set by vite.config.ts at build time. */
declare const __APP_VERSION__: string;

/** The slice of docs/readme/evaluation.json that lib/proof.ts reads (vite.config.ts, evaluationProof). */
declare module '*evaluation.json?proof' {
  const slice: import('./lib/proof').ProofSource;
  export default slice;
}

/** In trial pages only: what the trial answered in this browser and what was refused (src/trial/journal.ts). */
interface Window {
  shutterTrial?: { journal: import('./trial/journal').Journal };
}
