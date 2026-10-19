/// Sends an escalation a person reviewed and sent (T29): the "Escalation Mail" operation emails it, or writes it as
/// a file when no mail server is configured.
Class Shutter.Msg.EscalationSend Extends Ens.Request
{

/// The Shutter.Store.Escalation's id.
Property EscalationId As %String(MAXLEN = 20);

}
