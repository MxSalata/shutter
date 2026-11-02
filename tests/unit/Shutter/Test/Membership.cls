/// The approver check (Shutter.Util.Workflow.IsMember; CONTRACTS 5): a member of the Workflow role approves; a user marked
/// inactive in the Workflow engine does not, whatever the membership row says (v1.35).
Class Shutter.Test.Membership Extends %UnitTest.TestCase
{

Parameter USER = "ut-inactive-approver";

Parameter ROLE = "Shutter Approvers";

Method OnAfterAllTests() As %Status
{
    Do ..Purge()
    Quit $$$OK
}

ClassMethod Purge()
{
    If ##class(EnsLib.Workflow.RoleMembership).%ExistsId(..#ROLE _ "||" _ ..#USER) Do ##class(EnsLib.Workflow.RoleMembership).%DeleteId(..#ROLE _ "||" _ ..#USER)
    If ##class(EnsLib.Workflow.UserDefinition).%ExistsId(..#USER) Do ##class(EnsLib.Workflow.UserDefinition).%DeleteId(..#USER)
}

Method TestInactiveMemberIsNoApprover()
{
    Do ..Purge()
    Do $$$AssertNotTrue(##class(Shutter.Util.Workflow).IsMember(..#ROLE, ..#USER), "an unknown user is no member")
    Do $$$AssertStatusOK(##class(EnsLib.Workflow.UserDefinition).CreateUser(..#USER, "A test approver"), "a Workflow user")
    Do $$$AssertStatusOK(##class(EnsLib.Workflow.RoleDefinition).AddUserToRole(..#ROLE, ..#USER, 1, "Test"), "in the approvers' role")
    Do $$$AssertTrue(##class(Shutter.Util.Workflow).IsMember(..#ROLE, ..#USER), "an active member approves")
    Set u = ##class(EnsLib.Workflow.UserDefinition).%OpenId(..#USER)
    Set u.IsActive = 0
    Do $$$AssertStatusOK(u.%Save(), "marked inactive")
    Do $$$AssertNotTrue(##class(Shutter.Util.Workflow).IsMember(..#ROLE, ..#USER), "an inactive member does not, though the membership row stays")
    Do ..Purge()
}

}
