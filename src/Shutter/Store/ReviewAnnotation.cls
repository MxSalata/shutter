/// A person's standing judgement on a review finding (CONTRACTS 13): intended, an accepted risk or a demonstrated false
/// positive, bound to the finding's code, item, setting and the fingerprint of its effective value, never to one review
/// and never a change to the production. A finding of any later review with the same binding carries the status while
/// the annotation is unexpired and unrevoked; when the value changes, the annotation expires or is revoked, the finding
/// reopens as new. Approver-only. A revoked annotation is kept for the record.
Class Shutter.Store.ReviewAnnotation Extends (%Persistent, %JSON.Adaptor)
{

/// The review the annotation was made on, for the record; the binding below is what later reviews match.
Property ReviewId As %String(%JSONFIELDNAME = "reviewId", MAXLEN = 32);

Property FindingId As %String(%JSONFIELDNAME = "findingId", MAXLEN = 16);

Property Code As %String(%JSONFIELDNAME = "code", MAXLEN = 64);

Property Namespace As %String(%JSONFIELDNAME = "namespace", MAXLEN = 64);

Property Production As %String(%JSONFIELDNAME = "production", MAXLEN = 128);

/// The item the finding is about; empty for a finding about the production or the namespace.
Property Item As %String(%JSONFIELDNAME = "item", MAXLEN = 128);

Property Setting As %String(%JSONFIELDNAME = "setting", MAXLEN = 64);

/// SHA-256 of code|item|setting|found (Shutter.Review.Sweep.ValueFingerprint): the exact effective value accepted.
Property ValueFingerprint As %String(%JSONFIELDNAME = "valueFingerprint", MAXLEN = 80);

Index MatchIdx On (Namespace, Production, Code, Item);

Property Status As %String(%JSONFIELDNAME = "status", MAXLEN = 16, VALUELIST = ",intended,accepted_risk,false_positive");

Property Reason As %String(%JSONFIELDNAME = "reason", MAXLEN = 2000);

/// Who owns the exception (a team or a person), in the approver's words.
Property Owner As %String(%JSONFIELDNAME = "owner", MAXLEN = 100);

/// ISO UTC; empty means it does not expire.
Property ExpiresAt As %String(%JSONFIELDNAME = "expiresAt", MAXLEN = 30);

Property CreatedBy As %String(%JSONFIELDNAME = "createdBy", MAXLEN = 100);

Property CreatedAt As %String(%JSONFIELDNAME = "createdAt", MAXLEN = 30);

Property Revoked As %Boolean(%JSONFIELDNAME = "revoked") [ InitialExpression = 0 ];

Property RevokedAt As %String(%JSONFIELDNAME = "revokedAt", MAXLEN = 30);

Property RevokedBy As %String(%JSONFIELDNAME = "revokedBy", MAXLEN = 100);

Parameter STATUSES = "intended,accepted_risk,false_positive";

/// Whether a word is one of the three statuses.
ClassMethod IsStatus(status As %String) As %Boolean
{
    Quit ($LISTFIND($LISTFROMSTRING(..#STATUSES, ","), status) > 0)
}

/// Annotate a finding of a review: the binding (code, item, setting, value fingerprint) comes from the finding as the
/// review stored it. Refused for a finding id the review does not have or a status outside the three.
ClassMethod Create(review As Shutter.Store.Review, findingId As %String, status As %String, reason As %String, owner As %String, expiresAt As %String, createdBy As %String, Output a As Shutter.Store.ReviewAnnotation) As %Status
{
    Set a = ""
    If '$ISOBJECT(review) Quit $$$ERROR($$$GeneralError, "No review to annotate")
    If '..IsStatus(status) Quit $$$ERROR($$$GeneralError, "status must be one of " _ $REPLACE(..#STATUSES, ",", ", ") _ ", not '" _ status _ "'")
    Set f = review.Finding(findingId)
    If '$ISOBJECT(f) Quit $$$ERROR($$$GeneralError, "No finding " _ findingId _ " in review " _ review.ReviewId)
    Set a = ..%New()
    Set a.ReviewId = review.ReviewId, a.FindingId = findingId
    Set a.Namespace = review.Namespace, a.Production = review.Production
    Set a.Code = ##class(Shutter.Util.Json).Str(f, "code")
    Set a.Item = ##class(Shutter.Util.Json).Str(f, "item"), a.Setting = ##class(Shutter.Util.Json).Str(f, "setting")
    Set a.ValueFingerprint = ##class(Shutter.Review.Sweep).ValueFingerprint(a.Code, a.Item, a.Setting, ##class(Shutter.Util.Json).Str(f, "found"))
    Set a.Status = status, a.Reason = $EXTRACT(reason, 1, 2000), a.Owner = $EXTRACT(owner, 1, 100)
    Set a.ExpiresAt = expiresAt, a.CreatedBy = createdBy, a.CreatedAt = ##class(Shutter.Util.Time).NowUTC()
    Quit a.%Save()
}

/// The status an unexpired, unrevoked annotation gives a finding with this binding, the newest first, or "" when none;
/// annotationId is its id. An empty item or setting is matched as such (SQL sees an empty property as NULL).
ClassMethod StatusFor(code As %String, namespace As %String, production As %String, item As %String, setting As %String, valueFingerprint As %String, Output annotationId As %String) As %String
{
    Set annotationId = ""
    Set sql = "SELECT TOP 1 ID, Status FROM Shutter_Store.ReviewAnnotation WHERE Namespace = ? AND Production = ? AND Code = ? AND ValueFingerprint = ? AND Revoked = 0 AND (ExpiresAt IS NULL OR ExpiresAt > ?)"
    Set args = 5, args(1) = namespace, args(2) = production, args(3) = code, args(4) = valueFingerprint, args(5) = ##class(Shutter.Util.Time).NowUTC()
    If item = "" { Set sql = sql _ " AND Item IS NULL" } Else { Set sql = sql _ " AND Item = ?", args = args + 1, args(args) = item }
    If setting = "" { Set sql = sql _ " AND Setting IS NULL" } Else { Set sql = sql _ " AND Setting = ?", args = args + 1, args(args) = setting }
    Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, sql _ " ORDER BY ID DESC", args...)
    If 'rs.%Next() Quit ""
    Set annotationId = rs.%Get("ID")
    Quit rs.%Get("Status")
}

/// Withdraw the annotation: the finding reopens as new at the next read. The row stays for the record.
Method Revoke(by As %String) As %Status
{
    Set ..Revoked = 1, ..RevokedAt = ##class(Shutter.Util.Time).NowUTC(), ..RevokedBy = by
    Quit ..%Save()
}

ClassMethod ById(id As %String) As Shutter.Store.ReviewAnnotation
{
    If (id = "") || (id '= +id) Quit ""
    If '..%ExistsId(id) Quit ""
    Quit ..%OpenId(id)
}

/// The annotation as the API shows it (CONTRACTS 13).
Method ToObject() As %DynamicObject
{
    Set o = {}
    Set o.annotationId = ..%Id()
    Set o.code = ..Code, o.item = ..Item, o.setting = ..Setting, o.valueFingerprint = ..ValueFingerprint
    Set o.status = ..Status, o.reason = ..Reason, o.owner = ..Owner
    If ..ExpiresAt '= "" { Set o.expiresAt = ..ExpiresAt } Else { Do o.%Set("expiresAt", "", "null") }
    Set o.createdAt = ..CreatedAt
    Quit o
}

Storage Default
{
<Data name="ReviewAnnotationDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>ReviewId</Value>
</Value>
<Value name="3">
<Value>FindingId</Value>
</Value>
<Value name="4">
<Value>Code</Value>
</Value>
<Value name="5">
<Value>Namespace</Value>
</Value>
<Value name="6">
<Value>Production</Value>
</Value>
<Value name="7">
<Value>Item</Value>
</Value>
<Value name="8">
<Value>Setting</Value>
</Value>
<Value name="9">
<Value>ValueFingerprint</Value>
</Value>
<Value name="10">
<Value>Status</Value>
</Value>
<Value name="11">
<Value>Reason</Value>
</Value>
<Value name="12">
<Value>Owner</Value>
</Value>
<Value name="13">
<Value>ExpiresAt</Value>
</Value>
<Value name="14">
<Value>CreatedBy</Value>
</Value>
<Value name="15">
<Value>CreatedAt</Value>
</Value>
<Value name="16">
<Value>Revoked</Value>
</Value>
<Value name="17">
<Value>RevokedAt</Value>
</Value>
<Value name="18">
<Value>RevokedBy</Value>
</Value>
</Data>
<DataLocation>^Shutter.Store.ReviewAnnotationD</DataLocation>
<DefaultData>ReviewAnnotationDefaultData</DefaultData>
<IdLocation>^Shutter.Store.ReviewAnnotationD</IdLocation>
<IndexLocation>^Shutter.Store.ReviewAnnotationI</IndexLocation>
<StreamLocation>^Shutter.Store.ReviewAnnotationS</StreamLocation>
<Type>%Storage.Persistent</Type>
}
}
