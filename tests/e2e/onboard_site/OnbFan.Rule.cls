/// The rig's routing for OnbFan.Production: a message from the application FAN goes to both receivers, one from MAPPED through a
/// transform to the second, one from TWIN through two transforms to the first, so that a session sends it two messages; any other to one.
Class OnbFan.Rule Extends Ens.Rule.Definition
{
Parameter RuleAssistClass = "EnsLib.HL7.MsgRouter.RuleAssist";
XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.HL7.MsgRouter.RoutingEngine" production="OnbFan.Production">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="transform"><when condition="Document.{MSH:SendingApplication}=&quot;MAPPED&quot;"><send transform="OnbFan.WardMap" target="Fan Two"/><return/></when></rule>
<rule name="two"><when condition="Document.{MSH:SendingApplication}=&quot;TWIN&quot;"><send transform="OnbFan.WardMap" target="Fan One"/><send transform="OnbFan.TwinMap" target="Fan One"/><return/></when></rule>
<rule name="fan"><when condition="Document.{MSH:SendingApplication}=&quot;FAN&quot;"><send transform="" target="Fan One"/><send transform="" target="Fan Two"/><return/></when></rule>
<rule name="one"><when condition="1"><send transform="" target="Fan One"/><return/></when></rule>
</ruleSet>
</ruleDefinition>
}
}
