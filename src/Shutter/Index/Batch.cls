/// What Shutter's index adapter hands the indexer on each task (CONTRACTS 8.1, v1.31): the next batch of HL7 message headers
/// after the walk's high-water mark, on the watched routes and older than the lag, as parallel lists of header ids and body
/// ids in id order. The service indexes them; the adapter moves the mark to LastId once the service has taken the batch.
Class Shutter.Index.Batch Extends %RegisteredObject
{

/// The header ids, a $LIST in ascending order.
Property Ids As %String(MAXLEN = "");

/// The message body ids, a $LIST parallel to Ids.
Property BodyIds As %String(MAXLEN = "");

Property Count As %Integer [ InitialExpression = 0 ];

/// The mark the batch starts after.
Property AfterId As %Integer;

/// The last header id of the batch: the walk's next mark.
Property LastId As %Integer;

/// The routes the headers were taken from, as the adapter's setting says them.
Property Routes As %String(MAXLEN = 1000);

Method Add(id As %Integer, bodyId As %String)
{
    Set ..Ids = ..Ids _ $LISTBUILD(id), ..BodyIds = ..BodyIds _ $LISTBUILD(bodyId)
    Set ..Count = ..Count + 1, ..LastId = id
}

}
