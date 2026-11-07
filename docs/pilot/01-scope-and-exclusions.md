# Scope and exclusions

Agree this before anything is installed. Write the result in the [decision record](00-decision-record.md).

## What a pilot can cover at this release

- One Shutter namespace on its own, with your production hooked in ("shape A" in `docs/INSTALL.md`). Do not pilot with Shutter's items inside your own production: the stop in [07](07-stop-and-withdraw.md) relies on Shutter having its own connector items.
- Observation of failed HL7 deliveries in the namespaces you choose.
- Recovery only of ADT messages (admission, discharge and transfer), only to a receiver with an API that meets [06](06-receiver-acceptance.md).

## Always outside recovery

Shutter does not resend these. They may still open a case and a drafted email for a person.

| Excluded | What happens |
| --- | --- |
| Orders, results, documents and every other non-ADT message | A case and a draft, up to 2 MB |
| A receiver with no API, such as one that only takes HL7 over TCP | A case and a draft |
| Merges (forbidden as shipped: keep it so), and cancels the receiver can't reverse | Withheld for a person |
| A failed A08 patient-information update | Not recovered |

## What Shutter will not notice

Tell whoever owns the feed. Each of these needs an ordinary control that stays in place during the pilot.

- A message the engine counts as completed, then lost further on (a transport ACK, `GetReply` off, an application ACK that never comes). No case opens.
- Anything over 2 MB or not HL7. No case opens.
- A failure on an operation with `AlertOnError` off, or a failed forward while Shutter is down or refusing the sign-in. Forwards are never retried, so no case opens later.

## Your own exclusions

Shutter doesn't read the death or restriction fields, so a message about a death or a restricted record is treated like any other. Decide whether those patients and messages are in scope, and how you would keep them out.

Do not enable recovery if any of these is true:

- Your schema moves MSH-3, PID-3, PV1-3, PV1-19 or EVN-6. Shutter reads the standard positions.
- The visit number in PV1-19 is not unique at the receiver across every feed.
- Your feed's time zone without offsets isn't Europe/London. The clock-change stop covers only that zone.
- The receivers you want to recover answer on different hosts or ports. This version calls one.
- You rely on failover or a restored backup during the pilot. Neither has been tested.

## Worksheet

```text
Why are we doing this? What would we keep doing if we stopped?
Namespaces and productions in scope:
Receivers in scope, and each one's owner:
Triggers in scope:
Patients or messages excluded, and how:
Which ordinary alert or team still catches failures during the pilot?
```
