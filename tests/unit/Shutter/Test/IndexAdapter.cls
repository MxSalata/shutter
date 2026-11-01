/// Shutter's own inbound adapter for the index walk (Shutter.Index.Adapter, Shutter.Index.Batch, Shutter.Index.Indexer;
/// CONTRACTS 8.1, v1.31), read-only against this instance's message headers: the batch's shape and order, the routes
/// filter, the settings the production sees, and the indexer's take of a batch of messages already indexed.
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
