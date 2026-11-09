/// The outage email: for a receiver whose site profile entry has mail {"to": [...], "on": [...]}, one email when an outage
/// opens, goes to a person or closes, as on names, at most one every MINUTES minutes per receiver. It reads the outages'
/// events after its mark (kept in ^Shutter.OutageMail) and hands each email to Escalation Mail, which sends it or writes
/// an .eml file. The email names the receiver, its reading, the counts, the Do and Call lines and the page; never a
/// patient, a control id or a result: the outage's lists stay on the page.
///
/// Not in Shutter's production by default: a site that wants it adds the item, Outage Mailer, with this class.
Class Shutter.Operation.OutageMail Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

/// The fewest minutes between two emails about one receiver.
Parameter MINUTES = 10;

/// The item that sends the email.
Property Target As Ens.DataType.ConfigName [ InitialExpression = "Escalation Mail" ];

/// The address of Shutter's Incidents page, put in each email; empty, the email names the page without an address.
Property PageLink As %String(MAXLEN = 500);

Parameter SETTINGS = "Target:Basic,PageLink:Basic";

Method OnProcessInput(pInput As %RegisteredObject, Output pOutput As %RegisteredObject) As %Status
{
    Set sc = $$$OK
    Try {
        Set mark = $GET(^Shutter.OutageMail("mark"))
        // The first poll starts from now: an install with outages already recorded mails none of them.
        If mark = "" {
            &sql(SELECT MAX(ID) INTO :top FROM Shutter_Store.OutageEvent)
            Set ^Shutter.OutageMail("mark") = +$GET(top)
            Quit
        }
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID, OutageId, Kind FROM Shutter_Store.OutageEvent WHERE ID > ? ORDER BY ID", mark)
        While rs.%Next() {
            Do ..One(rs.%Get("OutageId"), rs.%Get("Kind"))
            Set ^Shutter.OutageMail("mark") = rs.%Get("ID")
        }
    } Catch err {
        Set sc = err.AsStatus()
    }
    Quit sc
}

/// One event: an email when its state is one the receiver's mail.on names and none went in the last MINUTES minutes.
Method One(outageId As %String, kind As %String)
{
    Set state = ..StateOf(kind)
    Quit:state=""
    Set row = ##class(Shutter.Store.Outage).%OpenId(outageId, 0)
    Quit:'$ISOBJECT(row)
    Set entry = ##class(Shutter.Store.SiteProfile).Receiver(row.Receiver)
    Set mail = $SELECT($ISOBJECT(entry) && (entry.%GetTypeOf("mail") = "object"): entry.mail, 1: "")
    Quit:'$ISOBJECT(mail)
    Set now = ##class(Shutter.Util.Time).NowUTC()
    Quit:'..Due(state, mail.%Get("on"), $GET(^Shutter.OutageMail("sent", row.Receiver)), now)
    Set email = ..Compose(##class(Shutter.API.Outages).One(row), state, ..PageLink)
    Set to = ""
    Set iter = mail.to.%GetIterator()
    While iter.%GetNext(, .a) { Set to = to _ $SELECT(to = "": "", 1: ",") _ a }
    Set request = ##class(Shutter.Msg.OutageMailSend).%New()
    Set request.OutageId = outageId, request.State = state, request.ToAddr = to, request.Subject = email.subject, request.Body = email.body
    Set sc = ..SendRequestAsync(..Target, request)
    If $$$ISOK(sc) Set ^Shutter.OutageMail("sent", row.Receiver) = now
}

/// The state an event is about, as mail.on names it: open, needs_person or closed; "" for any other event.
ClassMethod StateOf(kind As %String) As %String
{
    Quit $CASE(kind, "opened": "open", "open": "open", "needs_person": "needs_person", "closed": "closed", : "")
}

/// Whether an email is due: the state is one on names, and the last email about this receiver was MINUTES minutes ago or
/// more (an empty last means never).
ClassMethod Due(state As %String, on As %DynamicArray, last As %String, now As %String) As %Boolean
{
    Quit:'$ISOBJECT(on) 0
    Set named = 0
    Set iter = on.%GetIterator()
    While iter.%GetNext(, .s) { Set:s=state named = 1 }
    Quit:'named 0
    Quit:last="" 1
    Set ms = ##class(Shutter.Util.Time).MillisBetween(last, now)
    Quit (ms = "") || (ms >= (..#MINUTES * 60000))
}

/// The email for an outage as the routes give it (Shutter.API.Outages.One): {"subject", "body"}. The receiver, its
/// reading, the counts, the row's own Do and Call lines and the page; no list, so no control id, patient or result.
ClassMethod Compose(o As %DynamicObject, state As %String, link As %String = "") As %DynamicObject
{
    Set nl = $CHAR(13, 10), json = "Shutter.Util.Json"
    Set receiver = $CLASSMETHOD(json, "Str", o, "receiver")
    Set what = $CASE(state, "open": "an outage opened", "needs_person": "a person is needed", "closed": "the outage closed", : state)
    Set subject = "Shutter: " _ receiver _ ", " _ what
    Set where = $CLASSMETHOD(json, "Str", o, "item")
    Set:where'="" where = where _ $SELECT($CLASSMETHOD(json, "Str", o, "namespace") '= "": " in " _ $CLASSMETHOD(json, "Str", o, "namespace"), 1: "")
    Set b = "Receiver: " _ receiver _ $SELECT(where '= "": " (" _ where _ ")", 1: "") _ nl
    Set b = b _ "Outage " _ $CLASSMETHOD(json, "Str", o, "id") _ ": " _ what _ "; it reads " _ $TRANSLATE($CLASSMETHOD(json, "Str", o, "state"), "_", " ") _ "." _ nl
    Set reading = o.%Get("readings")
    If $ISOBJECT(reading) && ($CLASSMETHOD(json, "Str", reading, "reading") '= "") Set b = b _ "The engine's reading: " _ $TRANSLATE(reading.reading, "_", " ") _ "." _ nl
    Set settled = o.%Get("settled")
    If $ISOBJECT(settled) {
        Set b = b _ "Settled so far: " _ (+settled.completed) _ " Completed, " _ (+settled.error) _ " Error, " _ (+settled.suspended) _ " Suspended, " _ (+settled.other) _ " set aside." _ nl
    }
    Set lists = o.%Get("lists")
    If $ISOBJECT(lists) && $ISOBJECT(lists.%Get("offered")) && lists.offered.%Size() {
        Set b = b _ lists.offered.%Size() _ " message" _ $SELECT(lists.offered.%Size() = 1: " never reached", 1: "s never reached") _ " the receiver and " _ $SELECT(lists.offered.%Size() = 1: "is", 1: "are") _ " listed on the page for a person. Shutter will not send them." _ nl
    }
    Set words = o.%Get("words")
    If $ISOBJECT(words) {
        For key = "do", "call", "critical" {
            Set line = $CLASSMETHOD(json, "Str", words, key)
            Set:line'="" b = b _ line _ nl
        }
    }
    Set b = b _ nl _ $SELECT(link '= "": "The outage, its messages and what to do: " _ link, 1: "The outage, its messages and what to do are on Shutter's Incidents page.") _ nl
    Quit {"subject": (subject), "body": (b)}
}

}
