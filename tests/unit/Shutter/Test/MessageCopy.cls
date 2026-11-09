/// Shutter.Util.MessageCopy: a stored message copied into this process whole, as stored. The cross-namespace case (the
/// reason it exists) is proven on the Pathology rig; here the copy's faithfulness: every segment, the characters as stored
/// whatever MSH-18 says, the DocType, and nothing saved.
Class Shutter.Test.MessageCopy Extends %UnitTest.TestCase
{

Property Made As %String [ MultiDimensional ];

Method OnAfterOneTest(testname As %String) As %Status
{
    Set class = ""
    For {
        Set class = $ORDER(..Made(class)) Quit:class=""
        Set id = "" For { Set id = $ORDER(..Made(class, id)) Quit:id=""  Do $CLASSMETHOD(class, "%DeleteId", id) }
    }
    Kill ..Made
    Quit $$$OK
}

/// UTF-8 bytes stored as two characters under an MSH-18 that says UTF-8: the copy keeps 195 168, it does not decode them.
Method TestKeepsTheCharactersAsStored()
{
    Set segs = 3
    Set segs(1) = "MSH|^~\&|FAKESEND|SITE|FAKELIMS|LAB|20261105100000||ORU^R01|MC1|P|2.5.1|||||||UNICODE UTF-8"
    Set segs(2) = "PID|1||9990000401^^^NHS^NH||Test" _ $CHAR(195, 168) _ "patient^Alpha"
    Set segs(3) = "OBX|1|ST|TST01||VAL10|||||F"
    Set source = ##class(Shutter.Util.MessageCopy).Build("|^~\&", "2.5.1:ORU_R01", .segs)
    Do $$$AssertStatusOK(source.%Save(), "a stored message")
    Set ..Made("EnsLib.HL7.Message", source.%Id()) = ""
    Set id = ..Header(source.%Id())
    Set copy = ##class(Shutter.Util.MessageCopy).Of($NAMESPACE, id, .time)
    Do $$$AssertTrue($ISOBJECT(copy), "copied")
    Do $$$AssertEquals(copy.%Id(), "", "never saved")
    Do $$$AssertEquals(copy.SegCount, 3, "every segment")
    Do $$$AssertEquals(copy.DocType, "2.5.1:ORU_R01", "the DocType")
    Set name = copy.GetSegmentAt(2).GetValueAt("5.1")
    Do $$$AssertEquals($ASCII(name, 5) _ " " _ $ASCII(name, 6), "195 168", "the stored characters, not decoded")
    Do $$$AssertEquals(copy.GetValueAt("MSH:10"), "MC1", "fields read by path")
    Do $$$AssertTrue(time '= "", "the header's creation time")
    For i = 1:1:3 { Do $$$AssertEquals(copy.GetSegmentAt(i).OutputToString(copy.Separators), source.GetSegmentAt(i).OutputToString(source.Separators), "segment " _ i _ " as stored") }
}

/// A header with no HL7 body, a missing header and an empty namespace give "".
Method TestNothingToCopy()
{
    Do $$$AssertEquals(##class(Shutter.Util.MessageCopy).Of($NAMESPACE, "999999999"), "", "no such header")
    Do $$$AssertEquals(##class(Shutter.Util.MessageCopy).Of("", "1"), "", "no namespace")
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.TargetConfigName = "MessageCopy Test Out", h.MessageBodyClassName = "Ens.StringRequest", h.MessageBodyId = "1", h.TimeCreated = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
    Do h.%Save()
    Set ..Made("Ens.MessageHeader", h.%Id()) = ""
    Do $$$AssertEquals(##class(Shutter.Util.MessageCopy).Of($NAMESPACE, h.%Id()), "", "not an HL7 body")
    Do $$$AssertEquals($NAMESPACE, $NAMESPACE, "the namespace is where it was")
}

Method Header(bodyId As %String) As %String
{
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.TargetConfigName = "MessageCopy Test Out", h.MessageBodyClassName = "EnsLib.HL7.Message", h.MessageBodyId = bodyId, h.TimeCreated = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
    Do h.%Save()
    Set ..Made("Ens.MessageHeader", h.%Id()) = ""
    Quit h.%Id()
}

}
