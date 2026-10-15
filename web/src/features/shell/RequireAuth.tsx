import { Container } from '@mantine/core';
import { Navigate, Outlet, useLocation } from 'react-router';
import { useMe } from '@/api/hooks';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';

/** The gate for every signed-in page: asks the API who is signed in (GET /me), and sends anyone else to sign in. */
export function RequireAuth() {
  const me = useMe();
  const location = useLocation();
  if (me.isPending) return <PageSkeleton label="Checking your session…" />;
  if (me.isError)
    return (
      <Container size="sm" py={80}>
        <ErrorAlert title="Cannot reach Interlock's API" error={me.error} onRetry={() => void me.refetch()} />
      </Container>
    );
  if (!me.data) return <Navigate to="/login" replace state={{ from: location.pathname + location.search }} />;
  return <Outlet />;
}
