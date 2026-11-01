/// The Second Parser (Shutter.Util.SecondParser; CONTRACTS 6.7, v1.34): the gate's sentence from a report, and, where the jar
/// is in place, HAPI's report through the Java gateway on a sound message, a site category, a malformed field and garbage.
/// Without the jar the status says so and nothing fails.
Class Shutter.Test.SecondParser Extends %UnitTest.TestCase
{

Method TestVerdictWords()
{
    Set v = {"parsed": true, "second_parser": {"parser": "HAPI 2.6.0 (Java, PEX)", "parsed": true, "valid": true, "message_type": "ADT^A02^ADT_A02", "read_as": "2.5.1", "declared_version": "MYSITE_2.5.1"}}
    Set words = ##class(Shutter.Util.SecondParser).Verdict(v)
    Do $$$AssertTrue((words [ "well-formed ADT^A02^ADT_A02") && (words [ "declares MYSITE_2.5.1") && (words [ "schema is what this namespace lacks"), "a sound message of a site category: " _ words)
    Set v = {"parsed": false, "second_parser": {"parser": "HAPI 2.6.0 (Java, PEX)", "parsed": true, "valid": false, "errors": [{"code": "APPLICATION_INTERNAL_ERROR", "message": "ca.uhn.hl7v2.validation.ValidationException: Validation failed: Primitive value '1980-01-X1' requires to be empty or a HL7 datetime string at PID-7(0)", "segment": "PID", "field": 7}]}}
    Set words = ##class(Shutter.Util.SecondParser).Verdict(v)
    Do $$$AssertTrue((words [ "also finds it invalid at PID-7") && (words [ "Primitive value") && (words [ "malformed"), "a malformed field: " _ words)
    Set v = {"parsed": false, "second_parser": {"parser": "HAPI 2.6.0 (Java, PEX)", "parsed": false, "valid": false, "errors": [{"code": "APPLICATION_INTERNAL_ERROR", "message": "Determine encoding for message"}]}}
    Do $$$AssertTrue(##class(Shutter.Util.SecondParser).Verdict(v) [ "cannot read it either", "garbage: " _ ##class(Shutter.Util.SecondParser).Verdict(v))
    Do $$$AssertEquals(##class(Shutter.Util.SecondParser).Verdict({"parsed": false}), "", "no report, no words")
    Do $$$AssertEquals(##class(Shutter.Util.SecondParser).Verdict({"parsed": false, "second_parser": {"available": false, "reason": "x"}}), "", "an unavailable parser adds nothing")
    Do $$$AssertEquals(##class(Shutter.Util.SecondParser).Verdict(""), "", "nor does no validation")
}

Method TestStatusAndReports()
{
    Set s = ##class(Shutter.Util.SecondParser).Status()
    Do $$$AssertEquals(s.item, "Second Parser", "the item's name")
    Do $$$AssertTrue(s.jar [ "mgr/pex/shutter-pex.jar", "the jar under the manager directory: " _ s.jar)
    If 's.available {
        Do $$$AssertTrue(s.probe [ "no jar", "without the jar the status says what is missing: " _ s.probe)
        Do $$$AssertEquals(##class(Shutter.Util.SecondParser).Report("MSH|^~\&|A|B|C|D|20261101000000||ADT^A01|X|P|2.5.1", .err), "", "and a report is refused")
        Do $$$AssertTrue(err [ "pex/build.sh", "naming the build: " _ err)
        Quit
    }
    Do $$$AssertEquals(s.probe, "ok", "the gateway answers the probe: " _ s.probe)
    Do $$$AssertTrue((s.framework '= "") && (s."classpath_jars" = $LENGTH(##class(Shutter.Util.SecondParser).Classpath(), "|")), "the framework jar is named and the count is the classpath's: " _ s.framework _ " " _ s."classpath_jars")
    Do $$$AssertTrue(s.parser [ "HAPI", "and names HAPI: " _ s.parser)
    Set cr = $CHAR(13)
    Set sound = "MSH|^~\&|PAS|HOSP|DOWNSTREAM|HOSP|20261015092000||ADT^A02^ADT_A02|MSG00102|P|2.5.1" _ cr _ "EVN|A02|20261015092000||||20261015092000" _ cr _ "PID|1||MRN1001^^^HOSP^MR~9991001018^^^NHS^NH||SYNTH^ADA||19800101|F" _ cr _ "PV1|1|I|WARD-B^BAY2^04^HOSP|||WARD-A^BAY1^01^HOSP|||||||||||||ENC-1001|||||||||||||||||||||||||20261015090000"
    Set r = ##class(Shutter.Util.SecondParser).Report(sound, .err)
    Do $$$AssertTrue($ISOBJECT(r), "a report on a sound message: " _ err)
    Quit:'$ISOBJECT(r)
    Do $$$AssertTrue(r.parsed && r.valid && (r.structure = "ADT_A02") && (r."message_type" = "ADT^A02^ADT_A02"), "parsed and valid as ADT_A02: " _ r.%ToJSON())
    Do $$$AssertEquals(r.segments.%Size(), 4, "four segments")
    Set site = $REPLACE(sound, "|P|2.5.1", "|P|MYSITE_2.5.1")
    Set r = ##class(Shutter.Util.SecondParser).Report(site, .err)
    Do $$$AssertTrue($ISOBJECT(r) && r.parsed && r.valid && 'r."version_known" && (r."read_as" = "2.5.1") && (r."declared_version" = "MYSITE_2.5.1"), "a site category is read with the 2.5.1 structures and said so: " _ $SELECT($ISOBJECT(r): r.%ToJSON(), 1: err))
    Set bad = $REPLACE(sound, "19800101", "1980-01-X1")
    Set r = ##class(Shutter.Util.SecondParser).Report(bad, .err)
    Do $$$AssertTrue($ISOBJECT(r) && r.parsed && 'r.valid && (r.errors.%Size() > 0) && (r.errors.%Get(0).segment = "PID") && (r.errors.%Get(0).field = 7), "a malformed date is placed at PID-7: " _ $SELECT($ISOBJECT(r): r.%ToJSON(), 1: err))
    Set r = ##class(Shutter.Util.SecondParser).Report("hello" _ cr _ "world", .err)
    Do $$$AssertTrue($ISOBJECT(r) && 'r.parsed && 'r.valid && (r.errors.%Size() > 0), "garbage does not parse: " _ $SELECT($ISOBJECT(r): r.%ToJSON(), 1: err))
    Set noPid = $PIECE(sound, cr, 1) _ cr _ $PIECE(sound, cr, 2) _ cr _ $PIECE(sound, cr, 4)
    Set r = ##class(Shutter.Util.SecondParser).Report(noPid, .err)
    Do $$$AssertTrue($ISOBJECT(r) && r.parsed && 'r.valid && (r.errors.%Size() = 1) && (r.errors.%Get(0).code = "REQUIRED_SEGMENT_MISSING") && (r.errors.%Get(0).segment = "PID"), "a missing required segment is an error, not a pass: " _ $SELECT($ISOBJECT(r): r.%ToJSON(), 1: err))
    Set zed = sound _ cr _ "ZZZ|1|the site's own"
    Set r = ##class(Shutter.Util.SecondParser).Report(zed, .err)
    Do $$$AssertTrue($ISOBJECT(r) && r.parsed && r.valid && (r."custom_segments".%Size() = 1) && (r."custom_segments".%Get(0) = "ZZZ"), "a site Z segment is kept and named, not an error: " _ $SELECT($ISOBJECT(r): r.%ToJSON(), 1: err))
    Set v = {"parsed": false}
    Set v."second_parser" = r
    Do $$$AssertTrue(##class(Shutter.Util.SecondParser).Verdict(v) [ "the site segment ZZZ", "and the verdict names it: " _ ##class(Shutter.Util.SecondParser).Verdict(v))
    Set swapped = $PIECE(sound, cr, 1) _ cr _ $PIECE(sound, cr, 2) _ cr _ $PIECE(sound, cr, 4) _ cr _ $PIECE(sound, cr, 3)
    Set r = ##class(Shutter.Util.SecondParser).Report(swapped, .err)
    Do $$$AssertTrue($ISOBJECT(r) && 'r.valid && (r.errors.%Size() > 0), "segments out of order are an error: " _ $SELECT($ISOBJECT(r): r.%ToJSON(), 1: err))
    Set old = $REPLACE(sound, "|P|2.5.1", "|P|2.3.1")
    Set r = ##class(Shutter.Util.SecondParser).Report(old, .err)
    Do $$$AssertTrue($ISOBJECT(r) && r.parsed && r."version_known" && (r."declared_version" = "2.3.1") && (r."read_as" = "2.5.1"), "an older version is read with the canonical structures: " _ $SELECT($ISOBJECT(r): r.%ToJSON(), 1: err))
}

}
