/// The stream an answer of a FHIR receiver is read into. It takes no more bytes than its limit, so one request cannot
/// be made to hold an endless body: the connection's read ends at the first piece that would pass the limit. It also
/// takes nothing after its deadline, so an answer that outlasts its request is never read as the receiver's. A write
/// past either is an error, which ends the read where it stands; <property>Refused</property> then says which of the
/// two it was, and what the stream holds is only the start of the body.
/// <p>What the deadline does not do is shorten the wait. The connection hands a body sent under a Content-Length over
/// in one piece once all of it has come, and each of its waits ends only when no byte came for the adapter's response
/// timeout; the status line and the headers never reach a stream at all. A receiver that keeps sending a byte now
/// and then can therefore still hold the item for as long as it sends. This build has no timer that interrupts a
/// read, so that limit stands, and the deadline only decides what a late answer is worth.</p>
Class Shutter.FHIR.BoundedStream Extends %Stream.GlobalBinary
{

/// The most bytes it takes.
Property Limit As %Integer [ InitialExpression = 3000000, Transient ];

/// The $ZHOROLOG after which it takes nothing; "" for no deadline.
Property Deadline As %Numeric [ Transient ];

/// The bytes taken so far.
Property Taken As %Integer [ InitialExpression = 0, Transient ];

/// "" while nothing was refused, else "size" or "time".
Property Refused As %String [ Transient ];

/// A stream with that limit in bytes that takes nothing more than that many seconds from now; no seconds, no deadline.
ClassMethod Within(limit As %Integer, seconds As %Numeric = "") As Shutter.FHIR.BoundedStream
{
    Set stream = ..%New()
    Set stream.Limit = limit
    If seconds '= "" Set stream.Deadline = $ZHOROLOG + seconds
    Quit stream
}

Method Write(data As %String = "") As %Status
{
    If ..Refused '= "" Quit $$$ERROR($$$GeneralError, "The answer was already refused")
    If (..Deadline '= "") && ($ZHOROLOG > ..Deadline) {
        Set ..Refused = "time"
        Throw ##class(%Exception.General).%New("FHIRAnswerTooSlow", "5001", , "The answer was still arriving at the request's deadline")
    }
    If (..Taken + $LENGTH(data)) > ..Limit {
        Set ..Refused = "size"
        Throw ##class(%Exception.General).%New("FHIRAnswerTooLarge", "5001", , "The answer's body is over " _ ..Limit _ " bytes")
    }
    Set ..Taken = ..Taken + $LENGTH(data)
    Quit ##super(data)
}

}
