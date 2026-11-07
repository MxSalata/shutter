/// Whether a case's source is proved (CONTRACTS 11). The intake takes what a holder of the forwarder's sign-in posts: the source, the
/// receiver and the message all come from the caller. An automatic release writes with no person, so it needs more: the namespace
/// holds the header named, that header's message is the text received, and its session went to this receiver. A case the feed opened
/// itself has nothing to prove. This does not stop a genuine message being posted again. A site whose forwarder reports from another
/// instance, or under another namespace's name, turns it off with the profile's feed.prove_origin false.
Class Shutter.Operation.Origin
{

/// "" when the source is proved, or there is nothing to prove, or the site does not ask; otherwise why it is not proved, in words for a person.
ClassMethod Problem(case As Shutter.Store.Case, profile As %DynamicObject = "") As %String
{
    If '##class(Shutter.Store.SiteProfile).ProveOrigin(profile) Quit ""
    Set namespace = case.SourceNamespace, origin = case.OriginHeaderId, kind = case.FailureKind, receiver = case.Receiver
    If namespace = "" {
        If case.SourceHeaderId = "" Quit ""
        Set stored = ##class(Ens.MessageHeader).%OpenId(case.SourceHeaderId)
        If '$ISOBJECT(stored) Quit "its message header " _ case.SourceHeaderId _ " is not there"
        Quit $SELECT(stored.SourceConfigName = ..#INTAKEITEM: "the intake named no source namespace", 1: "")
    }
    If origin = "" Quit "the intake named no message header in " _ namespace
    Set received = ..TextOf(case.SourceHeaderId), problem = ""
    Try {
        New $NAMESPACE
        Set $NAMESPACE = namespace
        // From here the classes are the source namespace's: only the engine's own, and no method of this class.
        Set header = ##class(Ens.MessageHeader).%OpenId(origin)
        If '$ISOBJECT(header) Set problem = namespace _ " has no message header " _ origin Quit
        Set msg = "", cls = header.MessageBodyClassName
        If (cls '= "") && $CLASSMETHOD(cls, "%Extends", "EnsLib.HL7.Message") Set msg = $CLASSMETHOD(cls, "%OpenId", header.MessageBodyId)
        If '$ISOBJECT(msg) Set problem = "header " _ origin _ " in " _ namespace _ " holds no HL7 message" Quit
        If $TRANSLATE(msg.OutputToString(), $CHAR(10, 13)) '= received Set problem = "the text received is not the message of header " _ origin _ " in " _ namespace Quit
        // A message the service held never went to its receiver (kind unreadable): the header and the text are the proof.
        If kind = "unreadable" Quit
        Set reached = 0
        Set rs = ##class(%SQL.Statement).%ExecDirectNoPriv(, "SELECT TargetConfigName AS T FROM Ens.MessageHeader WHERE SessionId = ?", header.SessionId)
        While rs.%Next() {
            Set t = rs.%Get("T")
            Continue:t=""
            // The receiver as the site profile names it may carry the forwarder's prefix.
            If (t = receiver) || ($EXTRACT(receiver, *-$LENGTH(t), *) = (" " _ t)) Set reached = 1 Quit
        }
        If 'reached Set problem = "session " _ header.SessionId _ " in " _ namespace _ " sent nothing to " _ receiver
    } Catch ex {
        Set problem = "the namespace " _ namespace _ " could not be read: " _ ex.Name
    }
    Quit problem
}

/// The item that stores the intake's copy of a message.
Parameter INTAKEITEM = "Case Intake";

/// Shutter's stored copy of the message, with no line ends: what was received.
ClassMethod TextOf(headerId As %String) As %String
{
    Set text = ""
    Try {
        Set header = ##class(Ens.MessageHeader).%OpenId(headerId)
        If $ISOBJECT(header) Set text = $TRANSLATE($CLASSMETHOD(header.MessageBodyClassName, "%OpenId", header.MessageBodyId).OutputToString(), $CHAR(10, 13))
    } Catch ex {
        Set text = ""
    }
    Quit text
}

}
