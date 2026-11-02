/// A failure's signature (CONTRACTS 6.6, v1.35, "one board per failure signature"): what makes two cases the same
/// situation for the board. The receiver, the failure kind, the receiver's answer and the delivery word from the
/// condition vocabulary (6.1), the catalogue entry and outcome the match chose, the connector's error sentence with its
/// numbers normalised, the policy version, and the scenario stamp (a demo's scenarios never coalesce with each other; a
/// site's cases carry none). Pure functions of the case and its snapshot's summary.
Class Shutter.Util.Signature
{

/// The signature, "sha256:..." over the canonical JSON of the parts; "" when the case or summary is missing.
ClassMethod Of(case As Shutter.Store.Case, summary As %DynamicObject) As %String
{
    If '$ISOBJECT(case) || '$ISOBJECT(summary) Quit ""
    Quit ##class(Shutter.Util.Digest).OfObject(..Parts(case, summary))
}

/// The parts the signature is made of, for the record and the tests.
ClassMethod Parts(case As Shutter.Store.Case, summary As %DynamicObject) As %DynamicObject
{
    Set json = "Shutter.Util.Json"
    Set cat = summary.%Get("catalogue"), conds = $SELECT($ISOBJECT(cat): cat.%Get("conditions"), 1: "")
    Set p = {}
    Set p.receiver = case.Receiver, p."failure_kind" = case.FailureKind
    Set p."receiver_answer" = $SELECT($ISOBJECT(conds): $CLASSMETHOD(json, "Str", conds, "receiver_answer"), 1: "")
    Set p.delivery = $SELECT($ISOBJECT(conds): $CLASSMETHOD(json, "Str", conds, "delivery"), 1: "")
    Set p.entry = $SELECT($ISOBJECT(cat): $CLASSMETHOD(json, "Str", cat, "entry"), 1: "")
    Set p.outcome = $SELECT($ISOBJECT(cat): $CLASSMETHOD(json, "Str", cat, "outcome"), 1: "")
    Set p.error = ..Normalise(case.FailureText)
    Set p."policy_version" = ##class(Shutter.Operation.Gate).#POLICYVERSION
    Set p.scenario = case.Scenario
    Quit p
}

/// An error sentence with what varies between cases taken out: lower case, every run of digits as "#", hexadecimal
/// digests as "#", punctuation dropped, spaces collapsed, 160 characters at most.
ClassMethod Normalise(text As %String) As %String
{
    Set t = $ZCONVERT($GET(text), "L")
    Set t = ##class(%Regex.Matcher).%New("sha256:[0-9a-f]+", t).ReplaceAll("#")
    Set t = ##class(%Regex.Matcher).%New("[0-9]+", t).ReplaceAll("#")
    Set t = ##class(%Regex.Matcher).%New("[^a-z# ]+", t).ReplaceAll(" ")
    Set t = ##class(%Regex.Matcher).%New(" +", t).ReplaceAll(" ")
    Quit $EXTRACT($ZSTRIP(t, "<>W"), 1, 160)
}

}
