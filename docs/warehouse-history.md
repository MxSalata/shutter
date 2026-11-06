# Warehouse history: table specification and publication contract

Many receivers have no API that Shutter can read, but their data is pushed on a schedule into a data warehouse or a shadow database. A site can publish part of that data in the two tables below, so that the person working a failed message can see a patient's earlier movements beside the case.

It is **history for a person to read**, and nothing more.

- It answers: what did this declared source export, as of this stated watermark?
- It does not answer: what does the receiver hold now, and may Shutter safely change it?

## What it never does

Warehouse history is advisory. It never supplies:

- the receiver's current state, version or epoch;
- a receipt, or proof that something was or was not delivered;
- proof that a patient or a movement is absent;
- a passed dry run;
- a superseding event that closes a case;
- a verification of a recovery.

It stays out of the case's operational timeline, the catalogue's matcher, the dispatch gate, the planner and the verifier, and it does not reach the investigating agents. A site whose receiver has no API gains no automatic recovery from it: the case's evidence and its possible outcomes are what they were without it.

## The tables

A site owns these tables and fills them with its own extract job. The specification is the same whichever system they are copied from. Shutter's reference reader reads them from one IRIS schema, `ShutterWH`. It does not connect to other databases.

### Rules for every column

- Times are UTC and carry no zone. A time that is not known stays null, and is never filled with the extract's own time.
- Identifiers are strings, never numbers. `00123` and `123` are two patients.
- Identifiers compare exactly, case included. In IRIS, a string column ignores case in comparisons unless it says otherwise (the default collation, `SQLUPPER`), so without `COLLATE %EXACT` the id `abc1` would also find `ABC1`. Every identifier column below says so. A table on another database needs the same behaviour.
- Booleans are 1 or 0.

### `ShutterWH.Batch`

One published snapshot: its manifest.

| Column | Type | Requirement |
|---|---|---|
| `DatasetId` | `VARCHAR(64)` | Part of the primary key. The site's name for this dataset |
| `BatchId` | `VARCHAR(64)` | Part of the primary key |
| `BatchSequence` | `BIGINT` | Goes up by at least one with each batch of a generation |
| `DatasetGeneration` | `VARCHAR(64)` | Changes when the export is rebuilt or reset, and `BatchSequence` may then start again |
| `SourceSystem` | `VARCHAR(100)` | The system the data was exported from |
| `ReceiverReference` | `VARCHAR(128)` | The receiver this dataset is declared to describe. A declaration, not something Shutter infers |
| `ExtractStartedAtUTC` | `TIMESTAMP` | When the extract started |
| `ExtractFinishedAtUTC` | `TIMESTAMP` | When the extract finished |
| `SourceWatermarkUTC` | `TIMESTAMP`, may be null | The latest source time known to be wholly included. Null when `WatermarkKnown` is 0 |
| `WatermarkKnown` | `BIT` | 0 when completeness cannot be stated |
| `HistoryCompleteFromUTC` | `TIMESTAMP`, may be null | The earliest time from which completeness is asserted |
| `PublishedAtUTC` | `TIMESTAMP` | When this batch was published. It says nothing about how fresh the source is |
| `Ready` | `BIT` | Set to 1 last, once every row is in place |
| `PublishedRows` | `BIGINT` | How many rows of `ShutterWH.Movement` this batch has |
| `SchemaVersion` | `INTEGER` | 1 for this specification |

Primary key: `(DatasetId, BatchId)`. Unique key: `(DatasetId, DatasetGeneration, BatchSequence)`.

### `ShutterWH.Movement`

One current revision of each source event within a batch.

| Column | Type | Requirement |
|---|---|---|
| `DatasetId`, `BatchId` | As above | Foreign key to the batch |
| `SourceEventId` | `VARCHAR(160)` | The source's stable identity for the event. Not a Shutter operation key |
| `Revision` | `INTEGER` | The source's or the export's revision of the event |
| `RecordStatus` | `VARCHAR(16)` | `active`, `cancelled` or `retracted` |
| `PatientAuthority` | `VARCHAR(100)` | Required: who assigned `PatientId` |
| `PatientId` | `VARCHAR(160)` | Required |
| `EncounterAuthority` | `VARCHAR(100)`, may be null | Never invented. Null means not known |
| `EncounterId` | `VARCHAR(160)`, may be null | As the source exported it |
| `EventKind` | `VARCHAR(32)` | `admit`, `transfer`, `discharge`, `update`, `cancel` or `other` |
| `EventTimeUTC` | `TIMESTAMP`, may be null | Null when not known |
| `TimePrecision` | `VARCHAR(16)` | `second`, `minute`, `date` or `unknown` |
| `SourceRecordedAtUTC` | `TIMESTAMP`, may be null | When it was entered at the source |
| `SourceModifiedAtUTC` | `TIMESTAMP`, may be null | When it was last changed at the source |
| `Ward` | `VARCHAR(100)`, may be null | The source's code |
| `Bed` | `VARCHAR(100)`, may be null | The source's code |
| `SupersedesEventId` | `VARCHAR(160)`, may be null | Only when the source says so explicitly |

Primary key: `(DatasetId, BatchId, SourceEventId)`. Index: `(DatasetId, BatchId, PatientAuthority, PatientId)`.

**Leave out** patient name, birth date, address, a national number added as a convenience, clinical notes, diagnoses and result content. If the identifier a site chooses is itself a national identifier, it is still personal data, and the site approves it as such. These tables hold personal data either way: the site's own rules on access and retention apply to them, and to the copies a read keeps in Shutter's store.

### Creating them on IRIS

Create the schema once, in the namespace the reader serves. The statements are also what Shutter's reference reader expects.

```sql
CREATE TABLE ShutterWH.Batch (
    DatasetId VARCHAR(64) COLLATE %EXACT NOT NULL,
    BatchId VARCHAR(64) COLLATE %EXACT NOT NULL,
    BatchSequence BIGINT NOT NULL,
    DatasetGeneration VARCHAR(64) COLLATE %EXACT NOT NULL,
    SourceSystem VARCHAR(100) NOT NULL,
    ReceiverReference VARCHAR(128) NOT NULL,
    ExtractStartedAtUTC TIMESTAMP NOT NULL,
    ExtractFinishedAtUTC TIMESTAMP NOT NULL,
    SourceWatermarkUTC TIMESTAMP,
    WatermarkKnown BIT NOT NULL,
    HistoryCompleteFromUTC TIMESTAMP,
    PublishedAtUTC TIMESTAMP NOT NULL,
    Ready BIT NOT NULL,
    PublishedRows BIGINT NOT NULL,
    SchemaVersion INTEGER NOT NULL,
    CONSTRAINT BatchPK PRIMARY KEY (DatasetId, BatchId),
    CONSTRAINT BatchSequenceKey UNIQUE (DatasetId, DatasetGeneration, BatchSequence)
);

CREATE TABLE ShutterWH.Movement (
    DatasetId VARCHAR(64) COLLATE %EXACT NOT NULL,
    BatchId VARCHAR(64) COLLATE %EXACT NOT NULL,
    SourceEventId VARCHAR(160) COLLATE %EXACT NOT NULL,
    Revision INTEGER NOT NULL,
    RecordStatus VARCHAR(16) NOT NULL,
    PatientAuthority VARCHAR(100) COLLATE %EXACT NOT NULL,
    PatientId VARCHAR(160) COLLATE %EXACT NOT NULL,
    EncounterAuthority VARCHAR(100) COLLATE %EXACT,
    EncounterId VARCHAR(160) COLLATE %EXACT,
    EventKind VARCHAR(32) NOT NULL,
    EventTimeUTC TIMESTAMP,
    TimePrecision VARCHAR(16) NOT NULL,
    SourceRecordedAtUTC TIMESTAMP,
    SourceModifiedAtUTC TIMESTAMP,
    Ward VARCHAR(100),
    Bed VARCHAR(100),
    SupersedesEventId VARCHAR(160) COLLATE %EXACT,
    CONSTRAINT MovementPK PRIMARY KEY (DatasetId, BatchId, SourceEventId),
    CONSTRAINT MovementBatchFK FOREIGN KEY (DatasetId, BatchId) REFERENCES ShutterWH.Batch (DatasetId, BatchId)
);

CREATE INDEX MovementPatient ON ShutterWH.Movement (DatasetId, BatchId, PatientAuthority, PatientId);
```

## How a site publishes

1. Each batch is a **whole snapshot** of the dataset's history from `HistoryCompleteFromUTC`, not the changes since the last batch. A reader looks at one batch only, so a row missing from the newest batch is not shown.
2. Insert the batch's manifest with `Ready = 0`, then its rows.
3. When `PublishedRows` equals the rows in place, set `Ready = 1`. That is the last step.
4. A batch with `Ready = 1` and its rows never change. A correction is a new batch, with the event's new `Revision` and, when it was cancelled or withdrawn, its `RecordStatus`.
5. Older batches may be removed once a newer one is ready, and never the newest ready one.

## The publication contract

The site states all of this before the dataset is used, and keeps it where the people using the panel can find it:

- which source system and which receiver the dataset represents;
- what the identifiers mean, and which authority assigns each one;
- the extract's schedule and its longest expected lag;
- whether cancellations and deletions appear in it, and how;
- how far back the history goes;
- whether late corrections are included;
- who watches for a failed publication, and who a person asks when the data looks wrong.

"The extract finished at 10:00" is not evidence that every source event up to 10:00 is present. Only `SourceWatermarkUTC` says that, and only as far as the site's job is right. When the site cannot state it, `WatermarkKnown` is 0, and the reader reports the age as unknown.

## The queries

There are three, all fixed. No table name, SQL fragment or condition comes from a browser or an agent, and a caller never supplies a patient: the patient is the case's own.

Choose the batch to read, the newest one published:

```sql
SELECT TOP 1
    DatasetId, BatchId, BatchSequence, DatasetGeneration,
    SourceSystem, ReceiverReference,
    SourceWatermarkUTC, WatermarkKnown,
    HistoryCompleteFromUTC, PublishedAtUTC, PublishedRows, SchemaVersion
FROM ShutterWH.Batch
WHERE DatasetId = ?
  AND Ready = 1
ORDER BY PublishedAtUTC DESC, BatchSequence DESC
```

`BatchSequence` alone would not do: it may start again in a new generation, and the last batch of the old one would then be chosen for ever.

Check that the batch holds what its manifest says:

```sql
SELECT COUNT(*) AS PresentRows
FROM ShutterWH.Movement
WHERE DatasetId = ?
  AND BatchId = ?
```

Then read the patient's rows from that batch, and only that batch:

```sql
SELECT TOP 201
    SourceEventId, Revision, RecordStatus,
    PatientAuthority, PatientId,
    EncounterAuthority, EncounterId,
    EventKind, EventTimeUTC, TimePrecision,
    SourceRecordedAtUTC, SourceModifiedAtUTC,
    Ward, Bed, SupersedesEventId
FROM ShutterWH.Movement
WHERE DatasetId = ?
  AND BatchId = ?
  AND PatientAuthority = ?
  AND PatientId = ?
ORDER BY EventTimeUTC DESC, SourceRecordedAtUTC DESC, SourceEventId DESC
```

At most 200 rows are returned. A row 201 means the list is cut short, and the reader says so. Rows with no event time sort last, so they are the first to be cut.

## What the wording must say

Whatever shows this data keeps its limits beside it:

- **Warehouse history: historical context only.** Source complete through: the watermark, or unknown. Read at: the time. This may be hours behind. It is not used to authorise or verify a resend.
- With no rows: no matching rows were returned from this batch. This does not establish that the patient or movement is absent at the receiver.

An encounter in these tables is shown as the source exported it. Shutter does not treat it as the case's visit, even when the two ids look the same, unless the same authority is stated for both.

It may help a person understand an earlier stay, frame a question to the source or receiver team, spot a historical discrepancy, or decide to seek more evidence.
