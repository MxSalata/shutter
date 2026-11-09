/// A recorded agent run: the response and the transcript, stored under a replay key. Recordings
/// for the demo scenarios are keyed by scenario, encounter, event, member and config version
/// (scenario:S2:ENC-1002:transfer|encounter|1) so that they replay on any instance;
/// recordings of other cases are keyed by the snapshot digest and replay only where the same
/// evidence recurs.
Class Shutter.Bridge.Record Extends (%Persistent, %JSON.Adaptor)
{

Property Key As %String(%JSONFIELDNAME = "key", MAXLEN = 400) [ Required ];

Index KeyIdx On Key [ Unique ];

Property AgentClass As %String(%JSONFIELDNAME = "agentClass", MAXLEN = 200);

Property ConfigVersion As %String(%JSONFIELDNAME = "configVersion", MAXLEN = 32);

Property MemberCode As %String(%JSONFIELDNAME = "memberCode", MAXLEN = 32);

Property SnapshotDigest As %String(%JSONFIELDNAME = "snapshotDigest", MAXLEN = 80);

Property CorrelationKey As %String(%JSONFIELDNAME = "correlationKey", MAXLEN = 200);

Property Model As %String(%JSONFIELDNAME = "model", MAXLEN = 100);

/// The response fields as JSON (Shutter.Bridge.Msg.AgentResponse.ToObject).
Property ResponseJSON As %String(%JSONFIELDNAME = "response", MAXLEN = "");

/// The conversation as the live runner exported it, when available.
Property TranscriptJSON As %String(%JSONFIELDNAME = "transcript", MAXLEN = "");

/// The tool calls of the recorded run, as an array.
Property ToolCallsJSON As %String(%JSONFIELDNAME = "toolCalls", MAXLEN = "");

Property RecordedAt As %String(%JSONFIELDNAME = "recordedAt", MAXLEN = 30);

Property Label As %String(%JSONFIELDNAME = "label", MAXLEN = 200);

/// The recording under exactly this key: a demo scenario's key names the scenario, the encounter, the event, the
/// member and the config version, and nothing else stands in for it.
ClassMethod Find(key As %String) As Shutter.Bridge.Record
{
    Set id = ""
    &sql(SELECT ID INTO :id FROM Shutter_Bridge.Record WHERE "Key" = :key)
    If (SQLCODE = 0) && (id '= "") Quit ..%OpenId(id)
    Quit ""
}

/// Store or replace the recording of a run. A run the API mimic answered (model mock, or its response saying so: IsMock)
/// is refused before anything is written: no model made it.
ClassMethod Store(spec As Shutter.Bridge.RunSpec, response As Shutter.Bridge.Msg.AgentResponse, transcript As %String = "", toolCalls As %String = "", Output record As Shutter.Bridge.Record) As %Status
{
    Set record = ""
    // The refusal is judged on what the row would hold, before the stored row under the key is touched.
    Set draft = ..%New()
    Set draft.Model = response.Model, draft.ResponseJSON = response.ToObject().%ToJSON()
    If ..IsMock(draft) Quit $$$ERROR($$$GeneralError, "A run the API mimic answered is never stored as a recording")
    If ##class(Shutter.Util.PageQuestion).IsPageRun(spec.AgentClass) Quit $$$ERROR($$$GeneralError, "A question about a page is never stored as a recording")
    Set key = spec.ReplayKey()
    Set record = ..Find(key)
    If '$ISOBJECT(record) Set record = ..%New(), record.Key = key
    Set record.AgentClass = spec.AgentClass, record.ConfigVersion = spec.ConfigVersion
    Set record.MemberCode = spec.MemberCode, record.SnapshotDigest = spec.SnapshotDigest
    Set record.CorrelationKey = spec.CorrelationKey, record.Model = response.Model
    Set record.ResponseJSON = draft.ResponseJSON
    Set record.TranscriptJSON = transcript, record.ToolCallsJSON = toolCalls
    Set record.RecordedAt = ##class(Shutter.Util.Time).NowUTC()
    Set record.Label = "Recorded from a live run (" _ response.Model _ ", " _ spec.Mode _ " mode), " _ (+response.PromptTokens) _ " in / " _ (+response.CompletionTokens) _ " out tokens"
    Quit record.%Save()
}

/// Whether a recording is one the API mimic answered: its model is mock, or the response it holds says model mock or
/// provider configuration ShutterMock. Such a recording is never stored (Store) or imported (ImportJSON, ImportDir): no
/// model made it, and a replay of it would pass the mimic's answer off as a model's.
ClassMethod IsMock(record As Shutter.Bridge.Record) As %Boolean
{
    If '$ISOBJECT(record) Quit 0
    If record.Model = "mock" Quit 1
    If record.ResponseJSON = "" Quit 0
    Set o = ##class(Shutter.Util.Json).Parse(record.ResponseJSON, .sc)
    If '$ISOBJECT(o) || 'o.%IsA("%DynamicObject") Quit 0
    If ##class(Shutter.Util.Json).Str(o, "model") = "mock" Quit 1
    Quit ##class(Shutter.Util.Json).Str(o, "provider_config") = "ShutterMock"
}

/// Fill a response from this recording.
Method ApplyTo(response As Shutter.Bridge.Msg.AgentResponse) As %Status
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
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID FROM Shutter_Bridge.Record ORDER BY ""Key""")
    While rs.%Next() {
        Set r = ..%OpenId(rs.%Get("ID"))
        Continue:'$ISOBJECT(r)
        Do r.%JSONExportToString(.json)
        Set name = $TRANSLATE(r.Key, ":|/\ ", "-----") _ ".json"
        Set f = ##class(%Stream.FileCharacter).%New()
        Set f.TranslateTable = "UTF8"
        Set sc = f.LinkToFile(dir _ name)
        Quit:$$$ISERR(sc)
        Do f.Write(json)
        Set sc = f.%Save()
        Quit:$$$ISERR(sc)
    }
    Quit $$$OK
}

/// Import one recording from its JSON (the export shape), replacing an existing key. Returns the
/// key, or the error text. A recording the API mimic answered (IsMock) is refused. Callable through SQL for loading
/// fixtures from outside the instance.
ClassMethod ImportJSON(json As %String) As %String [ SqlProc ]
{
    Set json = ..Normalise(json)
    Set r = ..%New()
    Set sc = r.%JSONImport(json)
    If $$$ISERR(sc) Quit "ERROR: " _ $SYSTEM.Status.GetErrorText(sc)
    If ..IsMock(r) Quit "ERROR: a recording the API mimic answered (model mock) is never imported"
    Set existing = ..Find(r.Key)
    If $ISOBJECT(existing) {
        Set sc = existing.%JSONImport(json)
        If $$$ISOK(sc) Set sc = existing.%Save()
    } Else {
        Set sc = r.%Save()
    }
    If $$$ISERR(sc) Quit "ERROR: " _ $SYSTEM.Status.GetErrorText(sc)
    Quit r.Key
}

/// A recording file may hold the response, the transcript and the tool calls as JSON objects for
/// readability; the properties are strings, so they are serialised before the import.
ClassMethod Normalise(json As %String) As %String
{
    Try {
        Set o = ##class(%DynamicObject).%FromJSON(json)
        For key = "response", "transcript", "toolCalls" {
            Set type = o.%GetTypeOf(key)
            If (type = "object") || (type = "array") Do o.%Set(key, o.%Get(key).%ToJSON())
        }
        Return o.%ToJSON()
    } Catch ex {
        Return json
    }
}

/// Import every *.json recording in a directory, replacing existing keys. Returns the count. A file holding a recording
/// the API mimic answered (IsMock) fails the import, named in the error.
ClassMethod ImportDir(dir As %String, Output count As %Integer) As %Status
{
    Set count = 0, sc = $$$OK
    Set dir = ##class(%File).NormalizeDirectory(dir)
    If '##class(%File).DirectoryExists(dir) Quit $$$OK
    Set rs = ##class(%ResultSet).%New("%File:FileSet")
    Do rs.Execute(dir, "*.json")
    While rs.Next() {
        Set path = rs.Get("Name")
        // The recordings are UTF-8 (an arrow in a model's text): read without the table, each byte would be a character.
        Set json = ..Normalise(##class(Shutter.Knowledge.Text).ReadFile(path))
        Set r = ..%New()
        Set sc = r.%JSONImport(json)
        Quit:$$$ISERR(sc)
        If ..IsMock(r) Set sc = $$$ERROR($$$GeneralError, path _ ": a recording the API mimic answered (model mock) is never imported") Quit
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

Storage Default
{
<Data name="RecordDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Key</Value>
</Value>
<Value name="3">
<Value>AgentClass</Value>
</Value>
<Value name="4">
<Value>ConfigVersion</Value>
</Value>
<Value name="5">
<Value>MemberCode</Value>
</Value>
<Value name="6">
<Value>SnapshotDigest</Value>
</Value>
<Value name="7">
<Value>CorrelationKey</Value>
</Value>
<Value name="8">
<Value>Model</Value>
</Value>
<Value name="9">
<Value>ResponseJSON</Value>
</Value>
<Value name="10">
<Value>TranscriptJSON</Value>
</Value>
<Value name="11">
<Value>ToolCallsJSON</Value>
</Value>
<Value name="12">
<Value>RecordedAt</Value>
</Value>
<Value name="13">
<Value>Label</Value>
</Value>
</Data>
<DataLocation>^Shutter.Bridge.RecordD</DataLocation>
<DefaultData>RecordDefaultData</DefaultData>
<IdLocation>^Shutter.Bridge.RecordD</IdLocation>
<IndexLocation>^Shutter.Bridge.RecordI</IndexLocation>
<StreamLocation>^Shutter.Bridge.RecordS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
