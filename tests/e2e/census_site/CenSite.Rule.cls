/// The census rig's routing, by sending application: DBL sends two messages to one receiver in one session; BOTH goes to two
/// receivers; TWO and THREE to one each; anything else to the live receiver.
Class CenSite.Rule Extends Ens.Rule.Definition
{
Parameter RuleAssistClass = "EnsLib.HL7.MsgRouter.RuleAssist";
XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.HL7.MsgRouter.RoutingEngine" production="CenSite.Production">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="dbl"><when condition="Document.{MSH:SendingApplication}=&quot;DBL&quot;"><send transform="" target="Cen Two Sends"/><return/></when></rule>
<rule name="both"><when condition="Document.{MSH:SendingApplication}=&quot;BOTH&quot;"><send transform="" target="Cen Two"/><send transform="" target="Cen Three"/><return/></when></rule>
<rule name="two"><when condition="Document.{MSH:SendingApplication}=&quot;TWO&quot;"><send transform="" target="Cen Two"/><return/></when></rule>
<rule name="three"><when condition="Document.{MSH:SendingApplication}=&quot;THREE&quot;"><send transform="" target="Cen Three"/><return/></when></rule>
<rule name="out"><when condition="1"><send transform="" target="Cen Out"/><return/></when></rule>
</ruleSet>
</ruleDefinition>
}
}
