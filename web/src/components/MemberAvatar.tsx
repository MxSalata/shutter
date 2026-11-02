import { hueVar, memberIdentity } from '@/lib/hues';

/**
 * A board member's mark: its icon in its identity hue on a round surface (28 px; 16 px beside a citation line), or a
 * hollow ring for a member that did not take part. `muted` keeps the member's icon in gray, for one that is not
 * enabled. Decorative: the member's name always sits beside it.
 */
export function MemberAvatar({
  member,
  size = 28,
  hollow = false,
  muted = false,
}: {
  /** The member's code: conformance, encounter, impact, coordinator, generalist, or board for the board as a whole. */
  member: string;
  size?: number;
  hollow?: boolean;
  muted?: boolean;
}) {
  const { hue, icon: Icon } = memberIdentity(member);
  if (hollow)
    return (
      <span
        className="identity-dot"
        data-hollow
        style={{ width: size, height: size }}
        aria-hidden
        data-member={member}
      />
    );
  return (
    <span
      className="identity-mark"
      style={{
        width: size,
        height: size,
        borderRadius: '50%',
        ['--mark-hue' as string]: hueVar(muted ? 'gray' : hue),
      }}
      aria-hidden
      data-member={member}
      data-muted={muted || undefined}
    >
      <Icon size={Math.round(size * 0.6)} stroke={1.8} />
    </span>
  );
}
