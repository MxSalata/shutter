import { Anchor } from '@mantine/core';
import { Link } from 'react-router';
import { resolveCan } from '@/api/can';
import { useMe } from '@/api/hooks';
import { CLOSED_STATES, type CaseDetail } from '@/api/types';
import { isSiteEntryId } from '@/lib/siteEntry';

/**
 * "Make this one of our scenarios" (CONTRACTS 6.8): on a closed case, for a person who may change the site, the way to
 * the Site profile page's workbench with this case as the first one the new scenario must catch. Not on a case one of
 * the site's own scenarios already caught, nor on a case still being worked on, whose evidence can still change.
 */
export function OwnScenarioLink({ c, size = 'sm' }: { c: CaseDetail; size?: 'xs' | 'sm' }) {
  const can = resolveCan(useMe().data);
  if (!can.configure || !CLOSED_STATES.includes(c.state) || isSiteEntryId(c.catalogueEntry)) return null;
  return (
    <Anchor
      component={Link}
      size={size}
      to={`/site-profile?own=new&case=${encodeURIComponent(c.caseId)}`}
      data-testid="own-scenario-from-case"
    >
      Make this one of our scenarios
    </Anchor>
  );
}
