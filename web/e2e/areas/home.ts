import type { Area } from '../helpers';

/** The Home page, where the app opens, in Plain and in Technical. */
export const area: Area = {
  tag: '@home',
  screens: [
    { path: '/home', heading: 'Home' },
    { path: '/home', heading: 'Home', detail: 'technical' },
  ],
  liveScreens: [{ path: '/home', heading: 'Home' }],
  liveWordChecked: true,
};
