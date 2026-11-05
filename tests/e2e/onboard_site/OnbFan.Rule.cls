/// The rig's routing for OnbFan.Production: a message from the application FAN goes to both receivers, any other to one.
Class OnbFan.Rule Extends Ens.Rule.Definition
{
Parameter RuleAssistClass = "EnsLib.HL7.MsgRouter.RuleAssist";
XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.HL7.MsgRouter.RoutingEngine" production="OnbFan.Production">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="fan"><when condition="Document.{MSH:SendingApplication}=&quot;FAN&quot;"><send transform="" target="Fan One"/><send transform="" target="Fan Two"/><return/></when></rule>
<rule name="one"><when condition="1"><send transform="" target="Fan One"/><return/></when></rule>
</ruleSet>
</ruleDefinition>
}
}
