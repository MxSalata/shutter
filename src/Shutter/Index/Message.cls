/// The exact index of the HL7 messages Shutter watches (CONTRACTS 8): one row per message, keyed by the message body
/// id as every search table is, with the fields the evidence and the incidents search by: the visit number, the
/// patient identifier and its authority, the event and its time, the location, the source system and control id,
/// Shutter's own operation key, and the first route the message took. Shutter's indexer fills it
/// (Shutter.Index.Indexer); a site may also name it as a host's Search Table Class. IRIS removes the rows when the
/// messages are purged.
Class Shutter.Index.Message Extends Ens.CustomSearchTable
{

Parameter DOCCLASS = "EnsLib.HL7.Message";

/// PV1-19.1: the encounter.
Property VisitNumber As %String(COLLATION = "EXACT", MAXLEN = 100);

Index VisitNumber On VisitNumber;

/// The patient identifier (the PID-3 repetition typed MR, else the first) and its assigning authority.
Property PatientId As %String(COLLATION = "EXACT", MAXLEN = 100);

Index PatientId On PatientId;

Property PatientIdAuthority As %String(COLLATION = "EXACT", MAXLEN = 100);

/// MSH-9 as ADT_A02.
Property MessageType As %String(COLLATION = "EXACT", MAXLEN = 20);

Index MessageType On MessageType [ Type = bitmap ];

/// Shutter's word for the event (admit, transfer, discharge, update, register, preadmit, person_add, person_update,
/// cancel_admit, cancel_transfer, cancel_discharge, merge), or the trigger when none maps.
Property Event As %String(COLLATION = "EXACT", MAXLEN = 32);

/// MSH-10.
Property ControlId As %String(COLLATION = "EXACT", MAXLEN = 200);

Index ControlId On ControlId;

/// EVN-6, else EVN-2, else MSH-7, as ISO 8601 UTC.
Property EventTime As %String(COLLATION = "EXACT", MAXLEN = 30);

Index EventTime On EventTime;

/// PV1-3.1.
Property Location As %String(COLLATION = "EXACT", MAXLEN = 100);

/// MSH-3.
Property SourceSystem As %String(COLLATION = "EXACT", MAXLEN = 100);

/// Shutter's operation key, when the message maps to an operation.
Property OperationKey As %String(COLLATION = "EXACT", MAXLEN = 400);

Index OperationKey On OperationKey;

/// The first message header that carried the body: its id, source, target and time.
Property HeaderId As %String(MAXLEN = 20);

Property SourceConfigName As %String(COLLATION = "EXACT", MAXLEN = 128);

Index SourceConfigName On SourceConfigName [ Type = bitmap ];

Property TargetConfigName As %String(COLLATION = "EXACT", MAXLEN = 128);

/// The header's TimeCreated (UTC).
Property TimeCreated As %String(MAXLEN = 30);

Property IndexedAt As %String(MAXLEN = 30);

/// Fill a row from the message: Shutter's own mapping first (it knows the event words and the key), the raw fields
/// for what it leaves or cannot map, then the first header that carried the body.
ClassMethod OnIndexDoc(pDocObj As EnsLib.HL7.Message, pSearchTable As Shutter.Index.Message) As %Status
{
    Set sc = $$$OK
    Try {
        Set op = ##class(Shutter.Util.OperationKey).FromHL7(pDocObj, .osc)
        If $ISOBJECT(op) && $$$ISOK($GET(osc, 1)) {
            Set pSearchTable.OperationKey = ##class(Shutter.Util.Json).Str(op, "operation_key")
            Set pSearchTable.Event = ##class(Shutter.Util.Json).Str(op, "event")
            Set pSearchTable.VisitNumber = ##class(Shutter.Util.Json).Str(op, "encounter_id")
            Set pSearchTable.PatientId = ##class(Shutter.Util.Json).Str(op, "patient_id")
            Set pSearchTable.PatientIdAuthority = ##class(Shutter.Util.Json).Str(op, "patient_id_authority")
            Set pSearchTable.EventTime = ##class(Shutter.Util.Json).Str(op, "event_time")
            Set pSearchTable.Location = ##class(Shutter.Util.Json).Str(op, "ward")
            Set pSearchTable.SourceSystem = ##class(Shutter.Util.Json).Str(op, "source_system")
        }
        If pSearchTable.VisitNumber = "" Set pSearchTable.VisitNumber = ##class(Shutter.Util.OperationKey).Value(pDocObj, "PV1", "19.1")
        If pSearchTable.PatientId = "" {
            Set pSearchTable.PatientId = ##class(Shutter.Util.OperationKey).PatientIdentifier(pDocObj, .authority)
            If pSearchTable.PatientIdAuthority = "" Set pSearchTable.PatientIdAuthority = authority
        }
        If pSearchTable.Location = "" Set pSearchTable.Location = ##class(Shutter.Util.OperationKey).Value(pDocObj, "PV1", "3.1")
        If pSearchTable.SourceSystem = "" Set pSearchTable.SourceSystem = pDocObj.GetValueAt("MSH:3.1")
        Set type = pDocObj.GetValueAt("MSH:9.1"), trigger = pDocObj.GetValueAt("MSH:9.2")
        Set pSearchTable.MessageType = $SELECT(trigger = "": type, 1: type _ "_" _ trigger)
        If pSearchTable.Event = "" Set pSearchTable.Event = $SELECT(trigger = "": type, 1: trigger)
        Set pSearchTable.ControlId = pDocObj.GetValueAt("MSH:10")
        If pSearchTable.EventTime = "" {
            Set raw = pDocObj.GetValueAt("EVN:6.1")
            If raw = "" Set raw = pDocObj.GetValueAt("EVN:2.1")
            If raw = "" Set raw = pDocObj.GetValueAt("MSH:7.1")
            Set pSearchTable.EventTime = ##class(Shutter.Util.Time).FromHL7(raw)
        }
        Set bodyId = pDocObj.%Id(), hid = "", src = "", tgt = "", tc = ""
        &sql(SELECT TOP 1 ID, SourceConfigName, TargetConfigName, TimeCreated INTO :hid, :src, :tgt, :tc FROM Ens.MessageHeader WHERE MessageBodyClassName = 'EnsLib.HL7.Message' AND MessageBodyId = :bodyId ORDER BY ID)
        If SQLCODE = 0 Set pSearchTable.HeaderId = hid, pSearchTable.SourceConfigName = src, pSearchTable.TargetConfigName = tgt, pSearchTable.TimeCreated = tc
        // A message with no time of its own takes the header's, so every row sorts and merges.
        If (pSearchTable.EventTime = "") && (tc '= "") Set pSearchTable.EventTime = $TRANSLATE($PIECE(tc, ".", 1), " ", "T") _ "Z"
        Set pSearchTable.IndexedAt = ##class(Shutter.Util.Time).NowUTC()
    } Catch ex {
        Set sc = ex.AsStatus()
    }
    Quit sc
}

/// Whether a message body has its row already.
ClassMethod Indexed(bodyId As %String) As %Boolean
{
    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Index.Message WHERE DocId = :bodyId)
    Quit +n > 0
}

ClassMethod Count() As %Integer
{
    Set n = 0
    &sql(SELECT COUNT(*) INTO :n FROM Shutter_Index.Message)
    Quit +n
}

/// The rows for a visit number whose header is not older than a time, event time ascending, as objects. An empty
/// visit number, or the "-" piece of a message without one, has no rows: it would match every such message. With a
/// patient or an authority, a row naming another one is left out; a row that names none stays.
ClassMethod ForVisit(visitNumber As %String, since As %String = "", patientId As %String = "", authority As %String = "") As %DynamicArray
{
    Set out = []
    If (visitNumber = "") || (visitNumber = "-") Quit out
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Index.Message WHERE VisitNumber = ? AND (TimeCreated >= ? OR TimeCreated IS NULL) ORDER BY EventTime, ID", visitNumber, since)
    While rs.%Next() {
        Set r = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(r)
        Continue:((patientId '= "") && (r.PatientId '= "") && (r.PatientId '= patientId))
        Continue:((authority '= "") && (r.PatientIdAuthority '= "") && (r.PatientIdAuthority '= authority))
        Do out.%Push(r.ToObject())
    }
    Quit out
}

Method ToObject() As %DynamicObject
{
    Set o = {}
    Set o."message_body_id" = ..DocId, o."ens_header_id" = ..HeaderId, o."visit_number" = ..VisitNumber
    Set o."patient_id" = ..PatientId, o."patient_id_authority" = ..PatientIdAuthority
    Set o."message_type" = ..MessageType, o."event" = ..Event, o."control_id" = ..ControlId, o."event_time" = ..EventTime
    Set o.location = ..Location, o."source_system" = ..SourceSystem, o."operation_key" = ..OperationKey
    Set o.route = ..SourceConfigName _ $SELECT(..TargetConfigName '= "": " -> " _ ..TargetConfigName, 1: "")
    Set o."sent_at" = ..TimeCreated, o."indexed_at" = ..IndexedAt
    Quit o
}

Storage Default
{
<Data name="MessageDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>DocId</Value>
</Value>
<Value name="3">
<Value>PatientId</Value>
</Value>
<Value name="4">
<Value>PatientIdAuthority</Value>
</Value>
<Value name="5">
<Value>MessageType</Value>
</Value>
<Value name="6">
<Value>Event</Value>
</Value>
<Value name="7">
<Value>ControlId</Value>
</Value>
<Value name="8">
<Value>EventTime</Value>
</Value>
<Value name="9">
<Value>Location</Value>
</Value>
<Value name="10">
<Value>SourceSystem</Value>
</Value>
<Value name="11">
<Value>OperationKey</Value>
</Value>
<Value name="12">
<Value>HeaderId</Value>
</Value>
<Value name="13">
<Value>SourceConfigName</Value>
</Value>
<Value name="14">
<Value>TargetConfigName</Value>
</Value>
<Value name="15">
<Value>TimeCreated</Value>
</Value>
<Value name="16">
<Value>IndexedAt</Value>
</Value>
<Value name="17">
<Value>VisitNumber</Value>
</Value>
</Data>
<DataLocation>^Shutter.Index.MessageD</DataLocation>
<DefaultData>MessageDefaultData</DefaultData>
<IdLocation>^Shutter.Index.MessageD</IdLocation>
<IndexLocation>^Shutter.Index.MessageI</IndexLocation>
<StreamLocation>^Shutter.Index.MessageS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
