/// The library of board members: the specialist agents a user composes a board from, the
/// coordinator, and the generalist used as the single investigator. Each row names the agent class
/// that runs it (in the aihub module), its knowledge collection and the production item that
/// carries its runs.
Class Interlock.Store.BoardMember Extends (%Persistent, %JSON.Adaptor)
{

/// conformance, encounter, impact, coordinator, generalist, ...
Property Code As %String(%JSONFIELDNAME = "code", MAXLEN = 32) [ Required ];

Index CodeIdx On Code [ Unique ];

Property Name As %String(%JSONFIELDNAME = "name", MAXLEN = 100) [ Required ];

Property Description As %String(%JSONFIELDNAME = "description", MAXLEN = 1000);

/// What the member looks at, for the case page.
Property Perspective As %String(%JSONFIELDNAME = "perspective", MAXLEN = 500);

/// specialist, coordinator or generalist.
Property Role As %String(%JSONFIELDNAME = "role", MAXLEN = 16, VALUELIST = ",specialist,coordinator,generalist");

Property AgentClass As %String(%JSONFIELDNAME = "agentClass", MAXLEN = 200);

/// The knowledge base the member searches: contracts, lifecycle, effects, playbooks.
Property KnowledgeCollection As %String(%JSONFIELDNAME = "knowledgeCollection", MAXLEN = 100);

/// The production item (an Interlock.Bridge.Operation.Agent) that runs it.
Property ConfigItem As %String(%JSONFIELDNAME = "configItem", MAXLEN = 128) [ InitialExpression = "Agent Board" ];

/// submit_findings for specialists and the generalist's findings, submit_plan for a plan.
Property TerminalTool As %String(%JSONFIELDNAME = "terminalTool", MAXLEN = 32) [ InitialExpression = "submit_findings" ];

Property Enabled As %Boolean(%JSONFIELDNAME = "enabled") [ InitialExpression = 1 ];

/// Part of the default board for a new case.
Property InDefaultBoard As %Boolean(%JSONFIELDNAME = "inDefaultBoard") [ InitialExpression = 1 ];

Property Sort As %Integer(%JSONFIELDNAME = "sort") [ InitialExpression = 100 ];

/// Bumped whenever the member's instructions, tools or knowledge change; recorded on every run.
Property ConfigVersion As %String(%JSONFIELDNAME = "configVersion", MAXLEN = 32) [ InitialExpression = "1" ];

/// The members that review a case in a mode: the enabled default specialists for the board, the
/// generalist alone for single, none for rules. Returns a dynamic array of codes in sort order.
ClassMethod MembersForMode(mode As %String, requested As %DynamicArray = "") As %DynamicArray
{
    Set out = []
    If mode = "rules" Quit out
    If mode = "single" {
        Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Code FROM Interlock_Store.BoardMember WHERE Role = 'generalist' AND Enabled = 1 ORDER BY Sort")
        If rs.%Next() Do out.%Push(rs.%Get("Code"))
        Quit out
    }
    If $ISOBJECT(requested) && (requested.%Size() > 0) {
        Set iter = requested.%GetIterator()
        While iter.%GetNext(.i, .code) {
            Set m = ..ByCode(code)
            If $ISOBJECT(m) && m.Enabled && (m.Role = "specialist") Do out.%Push(code)
        }
        Quit out
    }
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Code FROM Interlock_Store.BoardMember WHERE Role = 'specialist' AND Enabled = 1 AND InDefaultBoard = 1 ORDER BY Sort")
    While rs.%Next() { Do out.%Push(rs.%Get("Code")) }
    Quit out
}

/// The coordinator member, or "" when none is enabled.
ClassMethod Coordinator() As Interlock.Store.BoardMember
{
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ID FROM Interlock_Store.BoardMember WHERE Role = 'coordinator' AND Enabled = 1 ORDER BY Sort")
    If rs.%Next() Quit ..%OpenId(rs.%Get("ID"))
    Quit ""
}

ClassMethod ByCode(code As %String) As Interlock.Store.BoardMember
{
    Set id = ""
    &sql(SELECT ID INTO :id FROM Interlock_Store.BoardMember WHERE Code = :code)
    If (SQLCODE '= 0) || (id = "") Quit ""
    Quit ..%OpenId(id)
}

/// The library's defaults. Existing rows keep their user edits; only missing rows are added.
ClassMethod Seed() As %Status
{
    Set sc = $$$OK
    Set defaults = [
        {"code": "conformance", "name": "Conformance", "role": "specialist", "sort": 10,
         "description": "Checks the failed message against the receiver's interface contract and message profile: structure, identifiers, required fields, supported versions.",
         "perspective": "Is the message itself acceptable to the receiver?",
         "agentClass": "Interlock.Agent.Conformance", "knowledge": "contracts"},
        {"code": "encounter", "name": "Encounter Integrity", "role": "specialist", "sort": 20,
         "description": "Reads the encounter's history on both sides, the ward's current state and version, and the lifecycle policy, to say whether the original intent still holds or a later event superseded it.",
         "perspective": "Does the business intent behind the message still hold?",
         "agentClass": "Interlock.Agent.Encounter", "knowledge": "lifecycle"},
        {"code": "impact", "name": "Impact Analysis", "role": "specialist", "sort": 30,
         "description": "Works out what a resend or a reconciliation would change downstream from the routing inventory and the effect contracts, and what it cannot know.",
         "perspective": "What would acting, or not acting, do to the systems that depend on this data?",
         "agentClass": "Interlock.Agent.Impact", "knowledge": "effects"},
        {"code": "coordinator", "name": "Coordinator", "role": "coordinator", "sort": 90,
         "description": "Reads the specialists' findings, keeps their disagreements, and proposes one exact plan from the recovery playbooks.",
         "perspective": "Given the findings, what is the one plan to put to the gate and to a person?",
         "agentClass": "Interlock.Agent.Coordinator", "knowledge": "playbooks", "terminal": "submit_plan"},
        {"code": "generalist", "name": "Single Investigator", "role": "generalist", "sort": 95,
         "description": "One agent with every tool and every knowledge collection, used as the single-investigator mode and as the comparison baseline for the board.",
         "perspective": "Everything at once.",
         "agentClass": "Interlock.Agent.Generalist", "knowledge": "all", "terminal": "submit_plan", "default": 0}
    ]
    Set iter = defaults.%GetIterator()
    While iter.%GetNext(.i, .d) {
        Continue:$ISOBJECT(..ByCode(d.code))
        Set m = ..%New()
        Set m.Code = d.code, m.Name = d.name, m.Role = d.role, m.Sort = d.sort
        Set m.Description = d.description, m.Perspective = d.perspective
        Set m.AgentClass = d.agentClass, m.KnowledgeCollection = d.knowledge
        Set m.TerminalTool = ##class(Interlock.Util.Json).Str(d, "terminal", "submit_findings")
        Set m.InDefaultBoard = ##class(Interlock.Util.Json).Bool(d, "default", 1)
        Set sc = m.%Save()
        Quit:$$$ISERR(sc)
    }
    Quit sc
}

}
