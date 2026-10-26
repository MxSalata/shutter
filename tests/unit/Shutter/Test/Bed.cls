/// The bed beside the ward (CONTRACTS 1.28, the bed-occupied case's first step): PV1-3's second component is the operation's
/// bed for an admission or a transfer and nothing else (the bed component with its room, PV1-3.3 within PV1-3.2), it stays outside the canonical payload so the digest is the one a
/// ward-level placement has, and the ward message sends it to the receiver.
Class Shutter.Test.Bed Extends %UnitTest.TestCase
{

Parameter A02 = "MSH|^~\\&|PAS|HOSP|DOWNSTREAM|HOSP|20261015082000||ADT^A02^ADT_A02|MSGB1|P|2.5.1<CR>EVN|A02|20261015082000<CR>PID|1||MRN9009^^^HOSP^MR||BED^TEST||19700101|M<CR>PV1|1|I|WARD-B^BAY1^B2^HOSP||||||||||||||||ENC-9009<CR>";

Parameter A02NOBED = "MSH|^~\\&|PAS|HOSP|DOWNSTREAM|HOSP|20261015082000||ADT^A02^ADT_A02|MSGB2|P|2.5.1<CR>EVN|A02|20261015082000<CR>PID|1||MRN9009^^^HOSP^MR||BED^TEST||19700101|M<CR>PV1|1|I|WARD-B^BAY1^^HOSP||||||||||||||||ENC-9009<CR>";

Parameter A03 = "MSH|^~\\&|PAS|HOSP|DOWNSTREAM|HOSP|20261015090000||ADT^A03^ADT_A03|MSGB3|P|2.5.1<CR>EVN|A03|20261015090000<CR>PID|1||MRN9009^^^HOSP^MR||BED^TEST||19700101|M<CR>PV1|1|I|WARD-B^BAY1^B2^HOSP||||||||||||||||ENC-9009<CR>";

ClassMethod Parse(text As %String, Output sc As %Status) As EnsLib.HL7.Message
{
    Set msg = ##class(EnsLib.HL7.Message).ImportFromString($REPLACE(text, "<CR>", $CHAR(13)), .sc)
    If $$$ISERR(sc) Quit ""
    Set docType = ##class(EnsLib.HL7.Schema).ResolveSchemaTypeToDocType("2.5.1", msg.Name, .sc)
    If $$$ISERR(sc) Quit ""
    If docType '= "" Do msg.PokeDocType(docType)
    Quit msg
}

Method TestBedInTheOperation()
{
    Set msg = ..Parse(..#A02, .sc)
    Do $$$AssertStatusOK(sc, "the A02 parses")
    Set op = ##class(Shutter.Util.OperationKey).FromHL7(msg, .sc)
    Do $$$AssertStatusOK(sc, "the A02 maps")
    Do $$$AssertEquals(op.event, "transfer", "a transfer")
    Do $$$AssertEquals(op.ward, "WARD-B", "to the ward")
    Do $$$AssertEquals(op.bed, "BAY1-B2", "and the bed, named within the ward by its room and bed components")
    Set plain = ##class(Shutter.Util.OperationKey).FromHL7(..Parse(..#A02NOBED, .sc), .sc)
    Do $$$AssertEquals(plain.%GetTypeOf("bed"), "null", "a room without a bed component: a bay-level placement, bed null")
    Do $$$AssertEquals(op."payload_digest", plain."payload_digest", "the bed is outside the canonical payload: the digest is the same")
    Do $$$AssertEquals(##class(Shutter.Util.Digest).WardPayloadDigest(op), op."payload_digest", "and recomputing it over the operation with the bed gives the same")
    Set discharge = ##class(Shutter.Util.OperationKey).FromHL7(..Parse(..#A03, .sc), .sc)
    Do $$$AssertStatusOK(sc, "the A03 maps")
    Do $$$AssertEquals(discharge.%GetTypeOf("bed"), "null", "a discharge carries no bed, whatever PV1-3 says")
}

Method TestBedOf()
{
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).BedOf("BAY1", "01"), "BAY1-01", "room and bed")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).BedOf("", "B2"), "B2", "a bed without a room")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).BedOf("BAY1", ""), "", "a room alone is no bed")
    Do $$$AssertEquals(##class(Shutter.Util.OperationKey).BedOf("", ""), "", "nothing")
}

Method TestBedInTheWardMessage()
{
    Set op = ##class(Shutter.Util.OperationKey).FromHL7(..Parse(..#A02, .sc), .sc)
    Set m = ##class(Shutter.Msg.WardOperation).FromOperation(op)
    Do $$$AssertEquals(m.Bed, "BAY1-B2", "the message carries the bed")
    Set body = m.ToWardJSON()
    Do $$$AssertEquals(body.bed, "BAY1-B2", "and sends it")
    Do $$$AssertEquals(body."payload_digest", op."payload_digest", "with the ward-level digest")
    Do $$$AssertNotTrue(m.ToOperation().%IsDefined("bed"), "the digest's shape has no bed")
    Set m.Event = "discharge"
    Do $$$AssertNotTrue(m.ToWardJSON().%IsDefined("bed"), "a discharge sends none")
}

}
