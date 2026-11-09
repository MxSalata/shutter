# Data flow and retention

For your information governance lead, and for a data protection impact assessment, which is yours to carry out. Treat everything here as personal data unless you decide otherwise. Tokens are pseudonyms, not anonymisation.

## Where data goes

| Route | What goes | Your decision |
| --- | --- | --- |
| Watched production to Shutter | The whole HL7 message, with its namespace, route and failure | Whether this copy is allowed; TLS (none by default); who holds the forwarder sign-in, which can open a case for any receiver |
| Shutter to a receiver (stage 3) | Operation key, patient and encounter ids, event, ward, bed, event time, source, expected version. No name or note | TLS (none by default). Ids in read addresses reach the receiver's access logs |
| Email to a team | Hospital number, NHS number, birth date, visit, event, failure text. A person sends it. Failure text goes as written, so may echo a name | Whether email is allowed, at what identification level; allowed domains; an SMTP server (without one, it's a file on disk and reads as sent) |
| Case evidence to a model (live agents only) | Tokens for identifiers; operational fields such as ward, bed and times; notes as flags only unless you turn free text on | **Recommended off for a pilot:** set no provider key, or install the core module. Any use needs its own approval, covering the provider's terms, region and retention |
| A person's question to a model (live agents only) | The typed text with known identifiers replaced. A name not in the message goes as typed | As above |
| Read-only tools for an outside client (AI Hub build) | Tokenised evidence; other text can carry identifiers until a board or question has run | Whether any client may connect, and where its data goes |
| The web app and Management Portal | Everything a role may read, whole messages included | Who holds which role; TLS and exposure are yours |

With no provider key, recorded runs are replayed for the shipped scenarios, a case with no recording takes the rules path, and nothing goes to a model. Check that on your own instance before relying on it: `SELECT Shutter.Setup_Doctor()` shows `provider` and `edition`.

## What stays inside, and for how long

| Store | Holds | Kept for, unless you change it |
| --- | --- | --- |
| Message store | Whole HL7 messages | No purge on a non-demo install: your own rules apply |
| Evidence snapshot | Patient name, identifiers, up to 50 notes with their text | **Indefinitely.** `PurgeClosedCases` on the "Shutter retention" task removes it 30 days after closing |
| Token map | **Identifiers, name parts and birth date in clear** | With the case, as above |
| Questions, findings, plans, events | Questions in clear; answers with identifiers restored | With the case, as above |
| Escalation emails | The text, and an `.eml` file with no SMTP server | Text removed 90 days after the case closed; the row stays. `0` keeps it |
| Recordings of agent runs | What a model saw and said, in tokens | Not purged by the retention task |
| Production reviews | May quote an HL7 segment | Not purged |

Not checked at this release: how long the message index and the Workflow inbox keep their rows. Check them on your instance. REST reads aren't audited by Shutter: what's recorded is whatever your IRIS auditing records.

## Agree and record

```text
Lawful basis and assessment reference:
Permitted destinations, each with TLS confirmed:
Who may hold each role:
Free text to a model (recommended: never):
Message purge: days, and who runs it:
Closed-case purge: on or off, and days:
Escalation days:
What is kept as pilot evidence, where, and until when:
Date everything else is deleted:
```
