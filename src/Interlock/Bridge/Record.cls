/// A recorded agent run: the response and the transcript, stored under a replay key. Recordings
/// for the demo scenarios are keyed by scenario and member so that they replay on any instance;
/// recordings of other cases are keyed by the snapshot digest and replay only where the same
/// evidence recurs.
Class Interlock.Bridge.Record Extends (%Persistent, %JSON.Adaptor)
{

Property Key As %String(%JSONFIELDNAME = "key", MAXLEN = 400) [ Required ];

Index KeyIdx On Key [ Unique ];

Property AgentClass As %String(%JSONFIELDNAME = "agentClass", MAXLEN = 200);

Property ConfigVersion As %String(%JSONFIELDNAME = "configVersion", MAXLEN = 32);

Property MemberCode As %String(%JSONFIELDNAME = "memberCode", MAXLEN = 32);

Property SnapshotDigest As %String(%JSONFIELDNAME = "snapshotDigest", MAXLEN = 80);

Property CorrelationKey As %String(%JSONFIELDNAME = "correlationKey", MAXLEN = 200);

Property Model As %String(%JSONFIELDNAME = "model", MAXLEN = 100);

/// The response fields as JSON (Interlock.Bridge.Msg.AgentResponse.ToObject).
Property ResponseJSON As %String(%JSONFIELDNAME = "response", MAXLEN = "");

/// The conversation as the live runner exported it, when available.
Property TranscriptJSON As %String(%JSONFIELDNAME = "transcript", MAXLEN = "");

/// The tool calls of the recorded run, as an array.
Property ToolCallsJSON As %String(%JSONFIELDNAME = "toolCalls", MAXLEN = "");

Property RecordedAt As %String(%JSONFIELDNAME = "recordedAt", MAXLEN = 30);

Property Label As %String(%JSONFIELDNAME = "label", MAXLEN = 200);

ClassMethod Find(key As %String) As Interlock.Bridge.Record
{
    Set id = ""
    &sql(SELECT ID INTO :id FROM Interlock_Bridge.Record WHERE "Key" = :key)
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ..%OpenId(id)
}

/// Store or replace the recording of a run.
ClassMethod Store(spec As Interlock.Bridge.RunSpec, response As Interlock.Bridge.Msg.AgentResponse, transcript As %String = "", toolCalls As %String = "", Output record As Interlock.Bridge.Record) As %Status
{
    Set key = spec.ReplayKey()
    Set record = ..Find(key)
    If '$ISOBJECT(record) Set record = ..%New(), record.Key = key
    Set record.AgentClass = spec.AgentClass, record.ConfigVersion = spec.ConfigVersion
    Set record.MemberCode = spec.MemberCode, record.SnapshotDigest = spec.SnapshotDigest
    Set record.CorrelationKey = spec.CorrelationKey, record.Model = response.Model
    Set record.ResponseJSON = response.ToObject().%ToJSON()
    Set record.TranscriptJSON = transcript, record.ToolCallsJSON = toolCalls
    Set record.RecordedAt = ##class(Interlock.Util.Time).NowUTC()
    Quit record.%Save()
}

/// Fill a response from this recording.
Method ApplyTo(response As Interlock.Bridge.Msg.AgentResponse) As %Status
{
    Set o = ##class(%DynamicObject).%FromJSON(..ResponseJSON)
    Set sc = response.FromObject(o)
    Quit sc
}

/// Export every recording to one JSON file per record in a directory.
ClassMethod ExportDir(dir As %String) As %Status
{
    Set dir = ##class(%File).NormalizeDirectory(dir)
    If '##class(%File).DirectoryExists(dir) Do ##class(%File).CreateDirectoryChain(dir)
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Interlock_Bridge.Record ORDER BY ""Key""")
    While rs.%Next() {
        Set r = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(r)
        Do r.%JSONExportToString(.json)
        Set name = $TRANSLATE(r.Key, ":|/\ ", "-----") _ ".json"
        Set f = ##class(%Stream.FileCharacter).%New()
        Set f.Filename = dir _ name
        Do f.Write(json)
        Set sc = f.%Save()
        Quit:$$$ISERR(sc)
    }
    Quit $$$OK
}

/// Import every *.json recording in a directory, replacing existing keys. Returns the count.
ClassMethod ImportDir(dir As %String, Output count As %Integer) As %Status
{
    Set count = 0, sc = $$$OK
    Set dir = ##class(%File).NormalizeDirectory(dir)
    If '##class(%File).DirectoryExists(dir) Quit $$$OK
    Set rs = ##class(%ResultSet).%New("%File:FileSet")
    Do rs.Execute(dir, "*.json")
    While rs.Next() {
        Set path = rs.Get("Name")
        Set f = ##class(%Stream.FileCharacter).%New()
        Set f.Filename = path
        Set json = f.Read($$$MaxStringLength)
        Set r = ..%New()
        Set sc = r.%JSONImport(json)
        Quit:$$$ISERR(sc)
        Set existing = ..Find(r.Key)
        If $ISOBJECT(existing) {
            Set sc = existing.%JSONImport(json)
            If $$$ISOK(sc) Set sc = existing.%Save()
        } Else {
            Set sc = r.%Save()
        }
        Quit:$$$ISERR(sc)
        Set count = count + 1
    }
    Quit sc
}

}
