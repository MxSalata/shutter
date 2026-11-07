Class DocSite.Rule Extends Ens.Rule.Definition
{
Parameter RuleAssistClass = "EnsLib.HL7.MsgRouter.RuleAssist";
XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.HL7.MsgRouter.RoutingEngine" production="DocSite.Production">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="refuse"><when condition='HL7.{1:5}="REFUSE"'><send transform="" target="Docs Refuse Out"/><return/></when></rule>
<rule name="plain"><when condition='HL7.{1:5}="PLAIN"'><send transform="" target="Docs Plain Out"/><return/></when></rule>
<rule name="half"><when condition='HL7.{1:5}="HALF"'><send transform="" target="Docs Half Out"/><return/></when></rule>
<rule name="dtl"><when condition='HL7.{1:5}="DTL"'><send transform="DocSite.Swap" target="Docs Out"/><return/></when></rule>
<rule name="touch"><when condition='HL7.{1:5}="TOUCH"'><send transform="DocSite.Touch" target="Docs Out"/><return/></when></rule>
<rule name="down"><when condition="1"><send transform="" target="Docs Out"/><return/></when></rule>
</ruleSet>
</ruleDefinition>
}
}
