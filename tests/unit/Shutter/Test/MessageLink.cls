/// The link to a message's page in the Management Portal (Shutter.API.Dispatch.MessageLink), which GET /cases/{id}/runs
/// gives with each agent run as messageLink. The page opens the header by the class its link names, and answers
/// "ERROR #5809: Object to Load not found, class ''" when the link names none, so the link names Ens.MessageHeader.
Class Shutter.Test.MessageLink Extends %UnitTest.TestCase
{

/// The page, the header's class, then its id, under the portal path given.
Method TestTheLinkNamesTheHeaderClass()
{
    Set link = ##class(Shutter.API.Dispatch).MessageLink(244, "/csp/healthshare/shutter/")
    Do $$$AssertEquals(link, "/csp/healthshare/shutter/EnsPortal.MessageContents.zen?HeaderClass=Ens.MessageHeader&HeaderId=244", "the page, the header's class, then its id")
    Set link = ##class(Shutter.API.Dispatch).MessageLink("66", "/csp/healthshare/hospital/")
    Do $$$AssertEquals(link, "/csp/healthshare/hospital/EnsPortal.MessageContents.zen?HeaderClass=Ens.MessageHeader&HeaderId=66", "under another namespace's portal path")
}

/// With no path given, the link is under the namespace's own portal path, as a case's Visual Trace links are.
Method TestTheNamespacesOwnPortal()
{
    Set portal = ##class(Shutter.API.Dispatch).PortalPath()
    Do $$$AssertEquals($EXTRACT(portal, *), "/", "the namespace's portal path ends in a slash")
    Set link = ##class(Shutter.API.Dispatch).MessageLink(9625)
    Do $$$AssertEquals(link, portal _ "EnsPortal.MessageContents.zen?HeaderClass=Ens.MessageHeader&HeaderId=9625", "under the namespace's own portal path")
}

/// The class the link names is the one that holds a production's headers: a header saved here is found by the link's
/// class and id, which is how the page opens it.
Method TestTheLinksClassHoldsTheHeader()
{
    Set h = ##class(Ens.MessageHeader).%New()
    Set h.SourceConfigName = "Unit Link In", h.TargetConfigName = "Unit Link Out", h.TimeCreated = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
    Do $$$AssertStatusOK(h.%Save(), "a header of the test's")
    Set id = h.%Id()
    Set query = $PIECE(##class(Shutter.API.Dispatch).MessageLink(id), "?", 2)
    Set first = $PIECE(query, "&", 1), second = $PIECE(query, "&", 2)
    Do $$$AssertEquals($PIECE(first, "=", 1) _ "," _ $PIECE(second, "=", 1), "HeaderClass,HeaderId", "the two parameters the page reads")
    Set class = $PIECE(first, "=", 2), linked = $PIECE(second, "=", 2)
    // Looked for before the test's header is removed, and the header is removed whatever the link said
    Set found = 0
    Try {
        Set found = $CLASSMETHOD(class, "%ExistsId", linked)
    } Catch {
    }
    Do ##class(Ens.MessageHeader).%DeleteId(id)
    Do $$$AssertEquals(class, "Ens.MessageHeader", "the link's class")
    Do $$$AssertEquals(linked, id, "the link's id")
    Do $$$AssertTrue(found, "the header is found by the link's class and id")
}

}
