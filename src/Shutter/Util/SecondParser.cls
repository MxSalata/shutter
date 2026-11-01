/// The Second Parser (CONTRACTS 6.7, v1.34): an independent HL7 parser, HAPI, run in Java through PEX, asked when IRIS cannot
/// read a message: is it well-formed and merely of a schema this namespace has not loaded, or malformed, and where. The
/// production path is the item "Second Parser" (EnsLib.PEX.BusinessOperation running shutter.pex.SecondParser from
/// shutter-pex.jar), which the Evidence Collector asks; this class knows where the jar is, whether it is there, the same
/// report through the Java gateway for the Doctor and the tests, and the one sentence the gate adds from a report. Without
/// the jar (a site without Java, the replay edition) nothing here fails: Available() is false, the evidence carries no
/// second opinion and the Doctor says why.
Class Shutter.Util.SecondParser
{

Parameter ITEM = "Second Parser";

Parameter CLASSNAME = "shutter.pex.SecondParser";

Parameter REPORTCLASS = "shutter.pex.Hl7Report";

/// The folder pex/build.sh fills: the jar and lib/ with HAPI and its dependencies, under the manager directory as pex/, beside
/// shutter/ and not inside it: the image's data volume covers shutter/, and a jar in there would outlive the image it came
/// with (an upgraded container would run the old one), while pex/ is the image's own and changes with it.
ClassMethod Dir() As %String
{
    Quit ##class(%File).NormalizeDirectory(##class(%File).ManagerDirectory() _ "pex")
}

ClassMethod Jar() As %String
{
    Quit ..Dir() _ "shutter-pex.jar"
}

/// Whether the jar is in place.
ClassMethod Available() As %Boolean
{
    Quit ##class(%File).Exists(..Jar())
}

/// Every jar the parser needs, as a list: the parser's own, then lib/*.jar.
ClassMethod Jars() As %List
{
    Set jars = $LISTBUILD(..Jar())
    Set rs = ##class(%ResultSet).%New("%File:FileSet")
    Do rs.Execute(..Dir() _ "lib", "*.jar", "Name", 0)
    While rs.Next() { Set jars = jars _ $LISTBUILD(rs.Get("Name")) }
    Quit jars
}

/// The jars as the PEX item's %gatewayExtraClasspaths setting wants them, separated by "|": IRIS's own PEX framework jar
/// (the Java side of PEX, which the gateway does not load by itself), the parser's jar and lib/*.jar.
ClassMethod Classpath() As %String
{
    Set framework = ..FrameworkJar()
    Quit $SELECT(framework '= "": framework _ "|", 1: "") _ $LISTTOSTRING(..Jars(), "|")
}

/// IRIS's PEX framework jar, the one holding com.intersystems.enslib.pex: the path pex/build.sh recorded in framework.txt
/// when it compiled against it (intersystems-utils-<v>.jar on IRIS 2026.2, intersystems-pex-<v>-shaded.jar on the AI Hub
/// images), else the first such name under dev/java/lib; "" when this install has none.
ClassMethod FrameworkJar() As %String
{
    Set recorded = ..Dir() _ "framework.txt"
    If ##class(%File).Exists(recorded) {
        Set f = ##class(%Stream.FileCharacter).%New()
        Do f.LinkToFile(recorded)
        Set path = $ZSTRIP(f.ReadLine(), "<>WC")
        If (path '= "") && ##class(%File).Exists(path) Quit path
    }
    Set lib = ##class(%File).NormalizeDirectory($SYSTEM.Util.InstallDirectory() _ "dev/java/lib")
    For pattern = "intersystems-pex-*.jar", "intersystems-utils-*.jar" {
        For sub = "1.8", "11", "" {
            Set dir = $SELECT(sub = "": lib, 1: ##class(%File).NormalizeDirectory(lib _ sub)), found = ""
            Continue:'##class(%File).DirectoryExists(dir)
            Set rs = ##class(%ResultSet).%New("%File:FileSet")
            Do rs.Execute(dir, pattern, "Name", 0)
            While rs.Next() { Set found = rs.Get("Name") }
            If found '= "" Quit
        }
        If $GET(found) '= "" Quit
    }
    Quit $GET(found)
}

/// The report on a raw HL7 text through the Java gateway directly, for the Doctor's probe and the tests (the production asks
/// the item instead, so the trace shows the exchange). "" when the jar is missing or the gateway fails; the error in Output.
ClassMethod Report(raw As %String, Output error As %String) As %DynamicObject
{
    Set error = ""
    If '..Available() Set error = "The parser's jar is not at " _ ..Jar() _ " (run pex/build.sh)" Quit ""
    Set report = ""
    Try {
        Set gw = $SYSTEM.external.getJavaGateway()
        Set jars = ..Jars()
        For i = 1:1:$LISTLENGTH(jars) { Do gw.addToPath($LIST(jars, i)) }
        Set json = gw.invoke(..#REPORTCLASS, "report", raw)
        Set report = ##class(%DynamicObject).%FromJSON(json)
    } Catch ex {
        Set error = $EXTRACT(ex.DisplayString(), 1, 500), report = ""
    }
    Quit report
}

/// What the Doctor says: {item, available, jar, classpath_jars, probe} (probe: "ok", or the error of a report on a one-line
/// message, only when the jar is there).
ClassMethod Status(probe As %Boolean = 1) As %DynamicObject
{
    Set s = {}
    Set s.item = ..#ITEM, s.jar = ..Jar()
    Do s.%Set("available", ..Available(), "boolean")
    Set s."classpath_jars" = $LISTLENGTH(..Jars())
    If ..Available() && probe {
        Set r = ..Report("MSH|^~\&|PAS|HOSP|SHUTTER|HOSP|20261101000000||ADT^A01^ADT_A01|PROBE|P|2.5.1" _ $CHAR(13) _ "EVN|A01|20261101000000" _ $CHAR(13) _ "PID|1||MRN1^^^HOSP^MR||PROBE^ONE||19800101|F" _ $CHAR(13) _ "PV1|1|I|WARD-A^BAY1^01^HOSP||||||||||||||||ENC-1", .error)
        Set s.probe = $SELECT($ISOBJECT(r) && ##class(Shutter.Util.Json).Bool(r, "parsed"): "ok", $ISOBJECT(r): "the probe message did not parse", 1: error)
        If $ISOBJECT(r) Set s.parser = ##class(Shutter.Util.Json).Str(r, "parser")
    } ElseIf '..Available() {
        Set s.probe = "no jar: the Second Parser item stays disabled and the evidence carries no second opinion (run pex/build.sh to add it)"
    }
    Quit s
}

/// The sentence the gate adds to SCHEMA_UNKNOWN and PARSE_FAILED from the validation's second_parser report: "" when there is
/// none or it was unavailable. A report that parsed and validated says the message is sound; one that did not names the
/// first error and where.
ClassMethod Verdict(validation As %DynamicObject) As %String
{
    If '$ISOBJECT(validation) Quit ""
    Set r = validation.%Get("second_parser")
    If '$ISOBJECT(r) || 'r.%IsDefined("parsed") Quit ""
    Set json = "Shutter.Util.Json", parser = $CLASSMETHOD(json, "Str", r, "parser", "an independent parser")
    If $CLASSMETHOD(json, "Bool", r, "parsed") && $CLASSMETHOD(json, "Bool", r, "valid") {
        Set what = $CLASSMETHOD(json, "Str", r, "message_type"), ver = $CLASSMETHOD(json, "Str", r, "read_as")
        Set declared = $CLASSMETHOD(json, "Str", r, "declared_version")
        // The site's own Z segments are kept and named: they are what the site's schema defines and this namespace lacks.
        Set custom = r.%Get("custom_segments"), zs = ""
        If $ISOBJECT(custom) { Set ci = custom.%GetIterator() While ci.%GetNext(, .z) { Set zs = zs _ $SELECT(zs = "": "", 1: ", ") _ z } }
        Quit "; " _ parser _ " reads it as a well-formed " _ $SELECT(what '= "": what, 1: "message") _ " with the " _ ver _ " structures" _ $SELECT(zs '= "": " and the site segment" _ $SELECT(zs [ ",": "s ", 1: " ") _ zs, 1: "") _ $SELECT((declared '= "") && (declared '= ver): " (it declares " _ declared _ ")", 1: "") _ ": the message is sound, and the schema" _ $SELECT(zs '= "": " that defines " _ zs, 1: "") _ " is what this namespace lacks"
    }
    Set errors = r.%Get("errors"), first = ""
    If $ISOBJECT(errors) && (errors.%Size() > 0) Set first = errors.%Get(0)
    Set where = ""
    If $ISOBJECT(first) {
        Set seg = $CLASSMETHOD(json, "Str", first, "segment"), field = $CLASSMETHOD(json, "Str", first, "field")
        If seg '= "" Set where = " at " _ seg _ $SELECT(+field > 0: "-" _ +field, 1: "")
        Set text = $CLASSMETHOD(json, "Str", first, "message")
        Set text = $PIECE(text, "ValidationException: ", *)
        Set text = $PIECE(text, "Validation failed: ", *)
        Set where = where _ $SELECT(text '= "": " (" _ $EXTRACT(text, 1, 200) _ ")", 1: "")
    }
    If $CLASSMETHOD(json, "Bool", r, "parsed") Quit "; " _ parser _ " reads its structure but also finds it invalid" _ where _ ": the message is malformed, not merely of an unknown schema"
    Quit "; " _ parser _ " cannot read it either" _ where _ ": the message is malformed"
}

}
