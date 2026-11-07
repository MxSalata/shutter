/// Reads one receiver's deliveries from a watched namespace for the failure coverage census (docs/CONTRACTS.md, section 17), as
/// plain data. It reads only: no lock, no write, no message content copied. Inside the other namespace only Ens, %SQL, %SYS and
/// the message classes the headers name are called, so the read does not depend on what is mapped there, as with
/// Shutter.Util.ProductionReader. A source that cannot be read gives readable false and the reason, never a count: a query
/// that fails returns a result set with a negative %SQLCODE and no rows, which unchecked would read as no failures.
Class Shutter.Util.CensusReader Extends %RegisteredObject
{

/// Ens.MessageHeader statuses that end a delivery as a failure: discarded, suspended, aborted, error. Completed (9) with the
/// error flag set is one too. The others are not finished yet.
Parameter FAILEDSTATUSES = ",4,5,7,8,";

/// The deliveries to target in [fromOdbc, toOdbc): at most maxHeaders of them, the failed ones in detail, and the session each
/// id in originIds (a %DynamicArray of header ids) belongs to, "" when that header is gone. toTarget is the number of different
/// messages the session sent the target: a resend of one body stays one.
ClassMethod Read(ns As %String, target As %String, fromOdbc As %String, toOdbc As %String, maxHeaders As %Integer, originIds As %DynamicArray) As %DynamicObject
{
    #define Check(%rs) If %rs.%SQLCODE < 0 { Throw ##class(%Exception.SQL).CreateFromSQLCODE(%rs.%SQLCODE, %rs.%Message) }
    Set data = {"namespace": (ns), "target": (target), "error": "", "scanned": 0, "completed": 0, "notFinished": 0, "missingIds": 0, "failures": [], "origins": {}}
    Do data.%Set("readable", 0, "boolean"), data.%Set("truncated", 0, "boolean"), data.%Set("reachesBack", 0, "boolean")
    Try {
        If '##class(%SYS.Namespace).Exists(ns) Set data.error = "The namespace " _ ns _ " does not exist" Quit
        New $NAMESPACE
        Set $NAMESPACE = ns
        // The deliveries. %String columns compare without case in SQL, and an item's name is exact: hence the check on each row.
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID, SessionId, Status, IsError, TimeCreated, TargetConfigName, MessageBodyClassName, MessageBodyId, Description FROM Ens.MessageHeader WHERE Type = 1 AND TargetConfigName = ? AND TimeCreated >= ? AND TimeCreated < ? ORDER BY ID", target, fromOdbc, toOdbc)
        $$$Check(rs)
        Set scanned = 0, completed = 0, unfinished = 0, truncated = 0, failures = data.failures
        While rs.%Next(.nextSc) {
            Continue:rs.%Get("TargetConfigName")'=target
            If scanned >= maxHeaders Set truncated = 1 Quit
            Set scanned = scanned + 1
            Set status = +rs.%Get("Status"), isError = ''rs.%Get("IsError")
            If (status '= 9) && (..#FAILEDSTATUSES '[ ("," _ status _ ",")) { Set unfinished = unfinished + 1 Continue }
            If (status = 9) && 'isError { Set completed = completed + 1 Continue }
            Set f = {"id": (rs.%Get("ID")), "session": (rs.%Get("SessionId")), "status": (status), "time": (rs.%Get("TimeCreated")), "bodyClass": (rs.%Get("MessageBodyClassName")), "bodyId": (rs.%Get("MessageBodyId")), "resendOf": ""}
            Do f.%Set("isError", isError, "boolean")
            // The engine's own words on a resent header: "Resent <id>", first the one it was resent from.
            Set said = rs.%Get("Description")
            If $EXTRACT(said, 1, 7) = "Resent " Set f.resendOf = +$EXTRACT(said, 8, *)
            Do failures.%Push(f)
        }
        If $$$ISERR($GET(nextSc, 1)) Throw ##class(%Exception.StatusException).CreateFromStatus(nextSc)
        $$$Check(rs)
        Set data.scanned = scanned, data.completed = completed, data.notFinished = unfinished
        Do data.%Set("truncated", truncated, "boolean")
        // Each failure's session and body.
        Set iter = failures.%GetIterator()
        While iter.%GetNext(.i, .f) {
            Set session = f.session
            If session = "" {
                Do f.%Set("hl7InSession", 0, "boolean")
                Set f.toTarget = 0
            } Else {
                If '$DATA(sessions(session)) {
                    Set hl7 = 0, n = 0
                    Kill bodies
                    Set s = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT Type, TargetConfigName, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE SessionId = ?", session)
                    $$$Check(s)
                    While s.%Next() {
                        Set cls = s.%Get("MessageBodyClassName")
                        If (cls '= "") && '$DATA(known(cls)) {
                            Set known(cls) = 0
                            Try { Set known(cls) = ''$CLASSMETHOD(cls, "%Extends", "EnsLib.HL7.Message") } Catch inner { Set known(cls) = 0 }
                        }
                        If (cls '= "") && known(cls) Set hl7 = 1
                        If (+s.%Get("Type") = 1) && (s.%Get("TargetConfigName") = target) {
                            Set one = cls _ "|" _ s.%Get("MessageBodyId")
                            If '$DATA(bodies(one)) Set bodies(one) = "", n = n + 1
                        }
                    }
                    $$$Check(s)
                    Set sessions(session) = $LISTBUILD(hl7, n)
                }
                Do f.%Set("hl7InSession", $LIST(sessions(session), 1), "boolean")
                Set f.toTarget = $LIST(sessions(session), 2)
            }
            Set present = 1, family = "", cls = f.bodyClass, body = f.bodyId
            If (cls '= "") && (body '= "") {
                Try {
                    Set present = ''$CLASSMETHOD(cls, "%ExistsId", body)
                    If present && $CLASSMETHOD(cls, "%Extends", "EnsLib.HL7.Message") {
                        // The message's structure, as ADT_A01, for its family: the one thing read from the body.
                        Set family = $PIECE($CLASSMETHOD(cls, "%OpenId", body, 0).Name, "_", 1)
                    }
                } Catch inner {
                    Set present = 0
                }
            }
            Do f.%Set("bodyPresent", present, "boolean")
            Set f.family = family
        }
        // Each origin a case names: its session, or "" when it is gone.
        Set iter = originIds.%GetIterator()
        While iter.%GetNext(.i, .id) {
            Set session = ""
            If id = +id {
                Set s = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT SessionId FROM Ens.MessageHeader WHERE ID = ?", id)
                $$$Check(s)
                If s.%Next() Set session = s.%Get("SessionId")
                $$$Check(s)
            }
            Do data.origins.%Set(id, session, "string")
        }
        // What is missing from the store: header ids are issued upwards, so a hole in those around the window is a purge or a
        // delete; a window with nothing before it, in a store that has issued earlier ids, reaches back past what is kept.
        Set s = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT MIN(ID) AS Lo, MAX(ID) AS Hi FROM Ens.MessageHeader WHERE TimeCreated >= ? AND TimeCreated < ?", fromOdbc, toOdbc)
        $$$Check(s)
        Set lo = "", hi = ""
        If s.%Next() Set lo = s.%Get("Lo"), hi = s.%Get("Hi")
        Set issued = +$GET(^Ens.MessageHeaderD)
        Set missing = 0, back = 0
        If lo '= "" {
            Set s = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT COUNT(*) AS N FROM Ens.MessageHeader WHERE ID >= ? AND ID <= ?", lo, hi)
            $$$Check(s)
            Do s.%Next()
            Set missing = (hi - lo + 1) - s.%Get("N")
            Set s = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 ID FROM Ens.MessageHeader WHERE ID < ? ORDER BY ID DESC", lo)
            $$$Check(s)
            If s.%Next() {
                Set missing = missing + (lo - s.%Get("ID") - 1)
            } ElseIf lo > 1 {
                Set back = 1
            }
            Set s = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 ID FROM Ens.MessageHeader WHERE ID > ? ORDER BY ID", hi)
            $$$Check(s)
            If s.%Next() {
                Set missing = missing + (s.%Get("ID") - hi - 1)
            } ElseIf issued > hi {
                Set missing = missing + (issued - hi)
            }
        } Else {
            Set s = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TOP 1 ID, TimeCreated FROM Ens.MessageHeader ORDER BY ID")
            $$$Check(s)
            If s.%Next() {
                If (s.%Get("ID") > 1) && (s.%Get("TimeCreated") ]] fromOdbc) Set back = 1
            } ElseIf issued > 0 {
                Set back = 1
            }
        }
        Set data.missingIds = missing
        Do data.%Set("reachesBack", back, "boolean")
        Do data.%Set("readable", 1, "boolean")
    } Catch ex {
        Do data.%Set("readable", 0, "boolean")
        Set data.error = $EXTRACT(ex.DisplayString(), 1, 300)
        Set data.failures = [], data.origins = {}
    }
    Quit data
}

}
