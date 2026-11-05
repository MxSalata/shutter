Class OnbDocs.Rule Extends Ens.Rule.Definition
{
Parameter RuleAssistClass = "EnsLib.HL7.MsgRouter.RuleAssist";
XData RuleDefinition [ XMLNamespace = "http://www.intersystems.com/rule" ]
{
<ruleDefinition alias="" context="EnsLib.HL7.MsgRouter.RoutingEngine" production="OnbDocs.Production">
<ruleSet name="" effectiveBegin="" effectiveEnd="">
<rule name="all"><when condition="1"><send transform="" target="Results Out"/><return/></when></rule>
</ruleSet>
</ruleDefinition>
}
}
