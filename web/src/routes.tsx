import { lazy } from 'react';
import { createHashRouter, Navigate } from 'react-router';
import { AppLayout } from './features/shell/AppLayout';
import { RequireAuth } from './features/shell/RequireAuth';
import { RouteError } from './features/shell/RouteError';

const LoginPage = lazy(() => import('./features/auth/LoginPage'));
const ScenariosPage = lazy(() => import('./features/scenarios/ScenariosPage'));
const CasesPage = lazy(() => import('./features/cases/CasesPage'));
const CasePage = lazy(() => import('./features/cases/CasePage'));
const IncidentsPage = lazy(() => import('./features/incidents/IncidentsPage'));
const IncidentPage = lazy(() => import('./features/incidents/IncidentPage'));
const SiteProfilePage = lazy(() => import('./features/site-profile/SiteProfilePage'));
const LibraryPage = lazy(() => import('./features/library/LibraryPage'));
const SettingsPage = lazy(() => import('./features/settings/SettingsPage'));
const EvaluationPage = lazy(() => import('./features/evaluation/EvaluationPage'));
const HealthPage = lazy(() => import('./features/health/HealthPage'));
const NotFoundPage = lazy(() => import('./features/shell/NotFoundPage'));

// Hash routing: IRIS serves the files at /shutter/ without rewriting unknown paths to index.html, so a deep link
// must not depend on the server.
export const router = createHashRouter([
  { path: '/login', element: <LoginPage />, errorElement: <RouteError /> },
  {
    element: <RequireAuth />,
    errorElement: <RouteError />,
    children: [
      {
        element: <AppLayout />,
        children: [
          { index: true, element: <Navigate to="/scenarios" replace /> },
          { path: 'scenarios', element: <ScenariosPage /> },
          { path: 'cases', element: <CasesPage /> },
          { path: 'cases/:caseId', element: <CasePage /> },
          { path: 'incidents', element: <IncidentsPage /> },
          { path: 'incidents/:incidentId', element: <IncidentPage /> },
          { path: 'site-profile', element: <SiteProfilePage /> },
          { path: 'library', element: <LibraryPage /> },
          { path: 'settings', element: <SettingsPage /> },
          { path: 'evaluation', element: <EvaluationPage /> },
          { path: 'health', element: <HealthPage /> },
          { path: '*', element: <NotFoundPage /> },
        ],
      },
    ],
  },
]);
