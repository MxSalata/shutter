import { hueVar, memberIdentity } from '@/lib/hues';

/**
 * A board member's mark: its icon in its identity hue on a round surface (28 px; 16 px beside a citation line), or a
 * hollow ring for a member that did not take part. Decorative: the member's name always sits beside it.
 */
export function MemberAvatar({
  member,
  size = 28,
  hollow = false,
}: {
  /** The member's code: conformance, encounter, impact, coordinator, generalist, or board for the board as a whole. */
  member: string;
  size?: number;
  hollow?: boolean;
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
      style={{ width: size, height: size, borderRadius: '50%', ['--mark-hue' as string]: hueVar(hue) }}
      aria-hidden
      data-member={member}
    >
      <Icon size={Math.round(size * 0.6)} stroke={1.8} />
    </span>
  );
}
