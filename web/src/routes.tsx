import { lazy } from 'react';
import { createHashRouter, Navigate, type RouteObject } from 'react-router';
import { AppLayout } from './features/shell/AppLayout';
import { RequireAuth } from './features/shell/RequireAuth';
import { RouteError } from './features/shell/RouteError';
import { TRIAL } from './env/mode';

// A trial page signs in with the trial's own roles and no password; a live page with the instance's sign-in
const LoginPage = TRIAL
  ? lazy(() => import('./trial/TrialSignIn'))
  : lazy(() => import('./features/auth/LoginPage'));
const HomePage = lazy(() => import('./features/home/HomePage'));
const ScenariosPage = lazy(() => import('./features/scenarios/ScenariosPage'));
const CasesPage = lazy(() => import('./features/cases/CasesPage'));
const CasePage = lazy(() => import('./features/cases/CasePage'));
const IncidentsPage = lazy(() => import('./features/incidents/IncidentsPage'));
const IncidentPage = lazy(() => import('./features/incidents/IncidentPage'));
const ReviewsPage = lazy(() => import('./features/reviews/ReviewsPage'));
const ReviewPage = lazy(() => import('./features/reviews/ReviewPage'));
const SiteProfilePage = lazy(() => import('./features/site-profile/SiteProfilePage'));
const LibraryPage = lazy(() => import('./features/library/LibraryPage'));
const SettingsPage = lazy(() => import('./features/settings/SettingsPage'));
const NamespacesPage = lazy(() => import('./features/namespaces/NamespacesPage'));
const EvaluationPage = lazy(() => import('./features/evaluation/EvaluationPage'));
const HealthPage = lazy(() => import('./features/health/HealthPage'));
const NotFoundPage = lazy(() => import('./features/shell/NotFoundPage'));

// Hash routing: IRIS serves the files at /shutter/ without rewriting unknown paths to index.html, so a deep link
// must not depend on the server.
export const routes: RouteObject[] = [
  { path: '/login', element: <LoginPage />, errorElement: <RouteError /> },
  {
    element: <RequireAuth />,
    errorElement: <RouteError />,
    children: [
      {
        element: <AppLayout />,
        children: [
          {
            // A page that fails (a render error, a chunk that no longer exists after a redeploy) shows its error in
            // the shell's outlet: the header and the navigation stay, so another page is one click away. The boundary
            // sits under AppLayout, since one on AppLayout's own route would replace the shell with the error.
            errorElement: <RouteError />,
            children: [
              { index: true, element: <Navigate to="/home" replace /> },
              { path: 'home', element: <HomePage /> },
              { path: 'scenarios', element: <ScenariosPage /> },
              { path: 'cases', element: <CasesPage /> },
              { path: 'cases/:caseId', element: <CasePage /> },
              { path: 'incidents', element: <IncidentsPage /> },
              { path: 'incidents/:incidentId', element: <IncidentPage /> },
              { path: 'reviews', element: <ReviewsPage /> },
              { path: 'reviews/:reviewId', element: <ReviewPage /> },
              { path: 'site-profile', element: <SiteProfilePage /> },
              { path: 'library', element: <LibraryPage /> },
              { path: 'settings', element: <SettingsPage /> },
              { path: 'settings/namespaces', element: <NamespacesPage /> },
              { path: 'evaluation', element: <EvaluationPage /> },
              { path: 'health', element: <HealthPage /> },
              { path: '*', element: <NotFoundPage /> },
            ],
          },
        ],
      },
    ],
  },
];

export const router = createHashRouter(routes);
