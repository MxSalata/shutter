// Runs before the bundle so the first paint already has the right colour scheme, contrast and
// palette (no white flash for dark-mode users, no white page before Pastel). Mirrors what Mantine
// and the appearance store decide once React is up; both keys are theirs, this only reads them.
(function () {
  try {
    var stored = localStorage.getItem('mantine-color-scheme-value');
    var scheme =
      stored === 'light' || stored === 'dark'
        ? stored
        : window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches
          ? 'dark'
          : 'light';
    document.documentElement.setAttribute('data-mantine-color-scheme', scheme);
  } catch (e) {
    /* storage unavailable: Mantine decides after boot */
  }
  try {
    var raw = localStorage.getItem('shutter.appearance');
    var state = (raw && JSON.parse(raw).state) || {};
    var setting = state.contrast || 'auto';
    var high =
      setting === 'high' ||
      (setting !== 'normal' && window.matchMedia && matchMedia('(prefers-contrast: more)').matches);
    document.documentElement.setAttribute('data-shutter-contrast', high ? 'high' : 'normal');
    // Stored as chosen; styles.css applies it only to the light scheme at normal contrast.
    document.documentElement.setAttribute(
      'data-shutter-palette',
      state.palette === 'pastel' ? 'pastel' : 'default',
    );
  } catch (e) {
    /* same */
  }
})();
