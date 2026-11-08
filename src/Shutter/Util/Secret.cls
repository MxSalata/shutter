/// A key typed into an agent item's Model or ProviderConfig setting by mistake: the one rule for what looks like a
/// secret, and the places that use it, so the value is shown and stored as "hidden" everywhere the setting is echoed
/// (the item's start line in the Event Log, the run's trace line and response, the stored run, the API's routes), as the
/// Portal Guide shows it, and a run with such a setting is refused before anything is looked up with it.
Class Shutter.Util.Secret
{

/// What a value that looks like a secret reads as.
Parameter HIDDEN = "hidden";

/// A value that looks like a secret or an address: a key's or a token's prefix (sk- where a word starts, anywhere in
/// the value; sk-ant, GitHub's ghp_, gho_ and github_pat_, Slack's xox, Stripe's sk_live_, sk_test_, rk_live_ and
/// rk_test_, GitLab's glpat- anywhere; Hugging Face's hf_ where a word starts), an AWS access key id (AKIA or ASIA and
/// sixteen capitals or digits), a Google API key (AIza and ten more), a JSON Web Token (eyJ, as {" starts in base64), a
/// PEM block (-----BEGIN), HTTP Basic credentials (basic and a base64 run holding a digit, +, / or =, or a capital
/// after a small letter, which a plain word does not), a credential written as a name and its value (key=, token=,
/// apikey:, secret= and the like), one run of 24 or more letters and digits holding both, as a random key is, a wallet
/// reference, a password, a URL or an address. With <var>model</var> set, the value is an agent item's Model, where a
/// lone "@" is a model's version (name@version, as one cloud names its models), not an address; every other shape counts.
ClassMethod Looks(value As %String, model As %Boolean = 0) As %Boolean
{
    Set v = $ZCONVERT(value, "L")
    If 'model && (v [ "@") Quit 1
    For word = "sk-ant", "secret://", "password", "bearer ", "://", "ghp_", "gho_", "github_pat_", "xox", "-----begin", "sk_live_", "sk_test_", "rk_live_", "rk_test_", "glpat-" {
        If v [ word Return 1
    }
    // Where a word starts, so task-runner and chf_rate are not keys.
    If $LOCATE(v, "(^|[^a-z0-9])(sk-|hf_)") Quit 1
    If $LOCATE(v, "(^|[^a-z0-9])(api[-_]?key|access[-_]?key|private[-_]?key|key|token|secret|passwd|pwd|auth)\s*[=:]") Quit 1
    If $LOCATE(value, "(^|[^A-Za-z0-9])(?i:basic)\s+(?=[A-Za-z0-9+/]*([0-9+/=]|[a-z][A-Z]))[A-Za-z0-9+/]{8,}") Quit 1
    // Where case tells a key from a word: AKIA or ASIA alone, or Asia/Kolkata, is not one.
    If value [ "eyJ" Quit 1
    If $LOCATE(value, "(AKIA|ASIA)[A-Z0-9]{16}") Quit 1
    If $LOCATE(value, "AIza[0-9A-Za-z_-]{10}") Quit 1
    If $LOCATE(value, "(?=[A-Za-z0-9]*[0-9])(?=[A-Za-z0-9]*[A-Za-z])[A-Za-z0-9]{24,}") Quit 1
    Quit 0
}

/// The value, or "hidden" when it looks like a secret.
ClassMethod Clean(value As %String) As %String
{
    Quit $SELECT(..Looks(value): ..#HIDDEN, 1: value)
}

/// Whether an agent item's Model looks like a key: the same rule, with a model's name@version let through.
ClassMethod LooksModel(value As %String) As %Boolean
{
    Quit ..Looks(value, 1)
}

/// An agent item's Model, or "hidden" when it looks like a key.
ClassMethod CleanModel(value As %String) As %String
{
    Quit $SELECT(..Looks(value, 1): ..#HIDDEN, 1: value)
}

/// The run's settings that came from the item: a ProviderConfig or a Model that looks like a key becomes "hidden" in
/// <var>spec</var>, so no runner, line or row ever gets the value. Returns the first such setting's name
/// (ProviderConfig, then Model), or "" when neither looks like one.
ClassMethod MaskSpec(spec As %RegisteredObject) As %String
{
    Set found = ""
    If (spec.ProviderConfig '= "") && ..Looks(spec.ProviderConfig) Set spec.ProviderConfig = ..#HIDDEN, found = "ProviderConfig"
    If (spec.Model '= "") && ..LooksModel(spec.Model) {
        Set spec.Model = ..#HIDDEN
        If found = "" Set found = "Model"
    }
    Quit found
}

/// Why a run that would call a model is refused when the item's <var>setting</var> looks like a key. It never repeats
/// the value.
ClassMethod Refusal(setting As %String) As %String
{
    Quit "the item's " _ setting _ " setting looks like a key; it was not used"
}

/// The response as it leaves the operation: its Model and ProviderConfig cleaned, and each of the item's own values in
/// <var>raw</var> (a list) and its <var>model</var> that looks like a key taken out of its Error, so neither the trace,
/// the message, nor any row made from it carries one.
ClassMethod MaskResponse(response As %RegisteredObject, raw As %List = "", model As %String = "")
{
    Set response.Model = ..CleanModel(response.Model), response.ProviderConfig = ..Clean(response.ProviderConfig)
    If response.Error '= "" Set response.Error = ..Scrub(response.Error, raw, model)
}

/// <var>text</var> with every value in <var>raw</var> (a list) that looks like a key, and <var>model</var> when it looks
/// like one as a Model, replaced by "hidden".
ClassMethod Scrub(text As %String, raw As %List = "", model As %String = "") As %String
{
    For i = 1:1:$LISTLENGTH(raw) {
        Set v = $LISTGET(raw, i)
        If (v '= "") && ..Looks(v) Set text = $REPLACE(text, v, ..#HIDDEN)
    }
    If (model '= "") && ..LooksModel(model) Set text = $REPLACE(text, model, ..#HIDDEN)
    Quit text
}

/// Runs stored before this rule (an install or an upgrade): a Model or ProviderConfig that looks like a key becomes
/// "hidden", and the value is taken out of the run's Error. Returns how many rows changed.
ClassMethod RepairRuns() As %Integer
{
    Set n = 0
    Try {
        // By SQL on both sides, so a copy of the row already open in this process is not what is written back.
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT ID, Model, ProviderConfig, Error FROM Shutter_Store.AgentRun WHERE Model IS NOT NULL OR ProviderConfig IS NOT NULL")
        While (rs.%SQLCODE = 0) && rs.%Next() {
            Set model = rs.%Get("Model"), config = rs.%Get("ProviderConfig")
            Continue:'(..LooksModel(model) || ..Looks(config))
            Set u = ##class(%SQL.Statement).%ExecDirectNoPriv(, "UPDATE Shutter_Store.AgentRun SET Model = ?, ProviderConfig = ?, Error = ? WHERE ID = ?", ..CleanModel(model), ..Clean(config), ..Scrub(rs.%Get("Error"), $LISTBUILD(config), model), rs.%Get("ID"))
            If u.%SQLCODE = 0 Set n = n + 1
        }
    } Catch ex {
    }
    Quit n
}

}
