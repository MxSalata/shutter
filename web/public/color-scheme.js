// Runs before the bundle so the first paint already has the right colour scheme (no white flash in dark mode).
// Mirrors what Mantine decides once React is up; the key is Mantine's, this only reads it.
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
})();
