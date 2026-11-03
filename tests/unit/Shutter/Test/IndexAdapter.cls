/// Shutter's own inbound adapter for the index walk (Shutter.Index.Adapter, Shutter.Index.Batch, Shutter.Index.Indexer;
/// CONTRACTS 8.1, v1.31), read-only against this instance's message headers: the batch's shape and order, the routes
/// filter, the settings the production sees, where a first walk starts, and the indexer's take of a batch of messages
/// already indexed.
Class Shutter.Test.IndexAdapter Extends %UnitTest.TestCase
{

Method TestNextBatchReadsInOrder()
{
    Set batch = ##class(Shutter.Index.Adapter).NextBatch(0, "ADT In", 5, 0, .error)
    Do $$$AssertEquals(error, "", "the walk reads without error")
    Do $$$AssertTrue($ISOBJECT(batch) && batch.%IsA("Shutter.Index.Batch"), "a batch comes back")
    Do $$$AssertTrue(batch.Count <= 5, "at most the batch size")
    Do $$$AssertEquals($LISTLENGTH(batch.Ids), batch.Count, "one id per header")
    Do $$$AssertEquals($LISTLENGTH(batch.BodyIds), batch.Count, "one body id per header")
    Set ordered = 1, prev = 0
    For i = 1:1:batch.Count { If +$LIST(batch.Ids, i) <= prev Set ordered = 0  Set prev = +$LIST(batch.Ids, i) }
    Do $$$AssertTrue(ordered, "ids ascend")
    If batch.Count > 0 Do $$$AssertEquals(batch.LastId, +$LIST(batch.Ids, batch.Count), "the last id is the next mark")
    Do $$$AssertEquals(batch.AfterId, 0, "the batch says what it came after")
    Do $$$AssertEquals(batch.Routes, "ADT In", "and its routes")
    // A route nobody sends on gives an empty batch, not an error.
    Set empty = ##class(Shutter.Index.Adapter).NextBatch(0, "No Such Route", 5, 0, .error)
    Do $$$AssertEquals(error _ "/" _ empty.Count, "/0", "an unknown route reads nothing")
    // After the newest header there is nothing.
    Set newest = ""
    &sql(SELECT MAX(ID) INTO :newest FROM Ens.MessageHeader)
    Set none = ##class(Shutter.Index.Adapter).NextBatch(+newest, "", 5, 0, .error)
    Do $$$AssertEquals(none.Count, 0, "nothing after the newest header")
}

Method TestSettingsAndWiring()
{
    Do $$$AssertEquals($PARAMETER("Shutter.Index.Indexer", "ADAPTER"), "Shutter.Index.Adapter", "the service names the adapter")
    Set settings = $PARAMETER("Shutter.Index.Adapter", "SETTINGS")
    Do $$$AssertTrue((settings [ "Routes") && (settings [ "BatchSize") && (settings [ "LagSeconds") && (settings [ "BackfillHours"), "the adapter carries the walk's settings")
    Do $$$AssertTrue(##class(Shutter.Index.Adapter).%Extends("Ens.InboundAdapter"), "it is an inbound adapter")
    Set a = ##class(Shutter.Index.Adapter).%New()
    Do $$$AssertEquals(a.Routes _ "|" _ a.BatchSize _ "|" _ a.LagSeconds _ "|" _ a.BackfillHours, "ADT In|200|5|168", "its defaults")
}

/// The first mark: a walk whose window holds headers starts at the first header inside it (the older ones are skipped), a
/// walk whose window holds none starts at the newest header, never at header 1; EnsureMark writes that mark.
Method TestFirstMarkStartsInsideTheWindow()
{
    Set newest = "", newestTs = "", oldest = "", oldestTs = ""
    &sql(SELECT MAX(ID), MIN(ID) INTO :newest, :oldest FROM Ens.MessageHeader)
    &sql(SELECT TimeCreated INTO :newestTs FROM Ens.MessageHeader WHERE ID = :newest)
    &sql(SELECT TimeCreated INTO :oldestTs FROM Ens.MessageHeader WHERE ID = :oldest)
    Do $$$AssertTrue(+newest > 0, "the instance has headers to walk")
    // A window that starts at the newest header's time: the walk begins one below the first header created since then.
    Set first = ""
    &sql(SELECT MIN(ID) INTO :first FROM Ens.MessageHeader WHERE TimeCreated >= :newestTs)
    Set mark = ##class(Shutter.Index.Adapter).FirstMark(newestTs)
    Do $$$AssertEquals(mark, first - 1, "the walk starts at the first header inside the window")
    Set inside = 0
    &sql(SELECT COUNT(*) INTO :inside FROM Ens.MessageHeader WHERE ID <= :mark AND TimeCreated >= :newestTs)
    Do $$$AssertEquals(inside, 0, "no header inside the window is below the mark")
    If newestTs ] oldestTs {
        Do $$$AssertTrue(mark >= oldest, "the headers older than the window are skipped (the oldest is " _ oldest _ ", the mark " _ mark _ ")")
    }
    // A window holding no header (it opens a day after the newest): the newest header, not header 1. The production may
    // write headers while this runs, so each answer is checked against the newest id read just before and just after it.
    &sql(SELECT MAX(ID) INTO :newest FROM Ens.MessageHeader)
    Set empty = ##class(Shutter.Index.Adapter).FirstMark($SYSTEM.SQL.Functions.DATEADD("day", 1, newestTs))
    &sql(SELECT MAX(ID) INTO :latest FROM Ens.MessageHeader)
    Do $$$AssertTrue((empty >= +newest) && (empty <= +latest), "an empty window starts at the newest header (" _ empty _ ", the newest " _ newest _ " to " _ latest _ ")")
    Do $$$AssertNotEquals(empty, 0, "and never at header 1")
    &sql(SELECT MAX(ID) INTO :newest FROM Ens.MessageHeader)
    Set none = ##class(Shutter.Index.Adapter).FirstMark("")
    &sql(SELECT MAX(ID) INTO :latest FROM Ens.MessageHeader)
    Do $$$AssertTrue((none >= +newest) && (none <= +latest), "no window starts at the newest header too (" _ none _ ", the newest " _ newest _ " to " _ latest _ ")")
    // EnsureMark writes the mark: the newest header without a back-fill, the first header in a window that holds them all.
    Set hwm = $GET(^Shutter.Index("hwm")), startedAt = $GET(^Shutter.Index("started_at"))
    Set a = ##class(Shutter.Index.Adapter).%New(), a.BackfillHours = 0
    Kill ^Shutter.Index("hwm")
    &sql(SELECT MAX(ID) INTO :newest FROM Ens.MessageHeader)
    Do a.EnsureMark()
    &sql(SELECT MAX(ID) INTO :latest FROM Ens.MessageHeader)
    Set written = $GET(^Shutter.Index("hwm"))
    Do $$$AssertTrue((written >= +newest) && (written <= +latest), "without a back-fill the high-water mark is the newest header (" _ written _ ", the newest " _ newest _ " to " _ latest _ ")")
    Set a.BackfillHours = 24 * 366 * 100
    Kill ^Shutter.Index("hwm")
    Do a.EnsureMark()
    Do $$$AssertEquals($GET(^Shutter.Index("hwm")), oldest - 1, "a window that holds every header starts the walk at the oldest")
    Do $$$AssertNotEquals($GET(^Shutter.Index("started_at")), "", "the start is recorded")
    If hwm '= "" { Set ^Shutter.Index("hwm") = hwm } Else { Kill ^Shutter.Index("hwm") }
    If startedAt '= "" { Set ^Shutter.Index("started_at") = startedAt } Else { Kill ^Shutter.Index("started_at") }
}

/// A batch of messages the index already holds adds nothing and fails nothing; a header without a body is skipped.
Method TestIndexerTakesABatch()
{
    Set batch = ##class(Shutter.Index.Adapter).NextBatch(0, "ADT In", 3, 0, .error)
    Set before = +$GET(^Shutter.Index("total"))
    Set sc = ##class(Shutter.Index.Indexer).IndexHeader(0, "", .added)
    Do $$$AssertStatusOK(sc, "a header without a body is taken")
    Do $$$AssertNotTrue(added, "and adds nothing")
    For i = 1:1:batch.Count {
        Set sc = ##class(Shutter.Index.Indexer).IndexHeader($LIST(batch.Ids, i), $LIST(batch.BodyIds, i), .added)
        Do $$$AssertStatusOK(sc, "header " _ $LIST(batch.Ids, i) _ " is taken")
    }
    Do $$$AssertTrue($ISOBJECT(##class(Shutter.Index.Indexer).Status()), "the status reads")
    Do $$$AssertEquals(##class(Shutter.Index.Indexer).Status().adapter, "Shutter.Index.Adapter", "and names the adapter")
}

}
