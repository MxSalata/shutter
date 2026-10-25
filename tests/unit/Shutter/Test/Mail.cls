/// The address and header rules of an escalation email (Shutter.Util.Mail, CONTRACTS 10), pure functions that read no
/// profile: every row of the table in XData Rows names its group (the test that runs it), the function ("address" by
/// default, "addresses", "domain" or "control"), the text given, the allowed domains when the function takes them and
/// the answer expected ("" when the text passes). No row is stored and no production runs.
Class Shutter.Test.Mail Extends %UnitTest.TestCase
{

Method TestOneAddressWithOneAt()
{
    Do ..RunRows("one_at")
}

Method TestEmptyListAllowsNone()
{
    Do ..RunRows("empty_list")
}

Method TestSubdomainsAndCase()
{
    Do ..RunRows("subdomains")
}

Method TestControlCharacters()
{
    Do ..RunRows("control")
}

Method TestBareAddresses()
{
    Do ..RunRows("bare")
}

Method TestDomainEntries()
{
    Do ..RunRows("domains")
}

/// The list read from a profile's mail.allowed_domains: lowercased, stripped, blanks and a missing array left out.
Method TestDomainsList()
{
    Do $$$AssertEquals($LISTLENGTH(##class(Shutter.Util.Mail).Domains([])), 0, "an empty array gives an empty list")
    Do $$$AssertEquals($LISTLENGTH(##class(Shutter.Util.Mail).Domains(["", " "])), 0, "blank entries are left out")
    Do $$$AssertEquals($LISTLENGTH(##class(Shutter.Util.Mail).Domains("")), 0, "no array gives an empty list")
    Do $$$AssertTrue($LISTSAME(##class(Shutter.Util.Mail).Domains(["NHS.NET ", "example.nhs.uk"]), $LISTBUILD("nhs.net", "example.nhs.uk")), "entries are lowercased and stripped")
}

/// The last defence of the .eml writer: a header value is one line whatever the row holds.
Method TestHeaderValue()
{
    Do $$$AssertEquals(##class(Shutter.Util.Mail).HeaderValue("x" _ $CHAR(13, 10) _ "Bcc: e@x"), "x  Bcc: e@x", "CR and LF become one space each")
    Do $$$AssertEquals(##class(Shutter.Util.Mail).HeaderValue("a" _ $CHAR(9) _ "b"), "a b", "a tab becomes a space")
    Do $$$AssertEquals(##class(Shutter.Util.Mail).HeaderValue("a" _ $CHAR(0) _ "b"), "ab", "another control character is removed")
    Do $$$AssertEquals(##class(Shutter.Util.Mail).HeaderValue("plain"), "plain", "plain text is unchanged")
}

/// Runs every row of a group: the function named, the text and the domains given, the answer expected.
Method RunRows(group As %String)
{
    Set n = 0
    Set iter = ..Rows().%GetIterator()
    While iter.%GetNext(.i, .row) {
        Continue:row.group'=group
        Set n = n + 1
        Set fn = ##class(Shutter.Util.Json).Str(row, "fn", "address"), text = row.%Get("text")
        Set domains = ##class(Shutter.Util.Mail).Domains(row.%Get("domains"))
        If fn = "address" {
            Set got = ##class(Shutter.Util.Mail).AddressProblem(text, domains)
        } ElseIf fn = "addresses" {
            Set got = ##class(Shutter.Util.Mail).AddressesProblem(text, domains)
        } ElseIf fn = "domain" {
            Set got = ##class(Shutter.Util.Mail).DomainProblem(text)
        } Else {
            Set got = ##class(Shutter.Util.Mail).ControlProblem(text)
        }
        Do $$$AssertEquals(got, row.expect, row.name _ ": " _ fn _ "(" _ ##class(Shutter.Util.Json).Preview(text) _ ")")
    }
    Do $$$AssertTrue(n > 0, "the group " _ group _ " has rows")
}

ClassMethod Rows() As %DynamicArray
{
    Set xdata = ##class(%Dictionary.CompiledXData).%OpenId($CLASSNAME() _ "||Rows")
    Quit ##class(%DynamicArray).%FromJSON(xdata.Data)
}

/// The table: group, name, the function (address when absent), the text, the allowed domains and the answer expected.
XData Rows [ MimeType = application/json ]
{
[
 {"group": "one_at", "name": "a second @ would hide the real domain", "text": "a@nhs.net@evil.com", "domains": ["nhs.net"], "expect": "must be one address with one @"},
 {"group": "one_at", "name": "no @ at all", "text": "anhs.net", "domains": ["nhs.net"], "expect": "must be one address with one @"},
 {"group": "one_at", "name": "outside the domains", "text": "a@evil.com", "domains": ["nhs.net"], "expect": "not in the allowed domains"},
 {"group": "one_at", "name": "inside the domains", "text": "a@nhs.net", "domains": ["nhs.net"], "expect": ""},
 {"group": "empty_list", "name": "no domains given", "text": "a@nhs.net", "expect": "no allowed mail domains are set in the site profile (mail.allowed_domains)"},
 {"group": "empty_list", "name": "an empty list", "text": "a@nhs.net", "domains": [], "expect": "no allowed mail domains are set in the site profile (mail.allowed_domains)"},
 {"group": "empty_list", "name": "blank entries only", "text": "a@nhs.net", "domains": ["", " "], "expect": "no allowed mail domains are set in the site profile (mail.allowed_domains)"},
 {"group": "empty_list", "name": "the shape is judged first", "text": "a@nhs.net@evil.com", "domains": [], "expect": "must be one address with one @"},
 {"group": "subdomains", "name": "a subdomain, whatever the case", "text": "A@Trust.NHS.net", "domains": ["nhs.net"], "expect": ""},
 {"group": "subdomains", "name": "the list's own case and spaces", "text": "a@nhs.net", "domains": ["NHS.NET "], "expect": ""},
 {"group": "subdomains", "name": "a longer name that only ends in the domain", "text": "a@xnhs.net", "domains": ["nhs.net"], "expect": "not in the allowed domains"},
 {"group": "subdomains", "name": "a trailing dot", "text": "a@nhs.net.", "domains": ["nhs.net"], "expect": "the domain is not a valid domain name"},
 {"group": "subdomains", "name": "an empty label", "text": "a@nhs..net", "domains": ["nhs.net"], "expect": "the domain is not a valid domain name"},
 {"group": "subdomains", "name": "a leading hyphen", "text": "a@-nhs.net", "domains": ["nhs.net"], "expect": "the domain is not a valid domain name"},
 {"group": "control", "name": "a header injected after an address", "text": "a@nhs.net\r\nBcc: x@nhs.net", "domains": ["nhs.net"], "expect": "must not contain line breaks or control characters"},
 {"group": "control", "fn": "addresses", "name": "a header injected in a list", "text": "a@nhs.net\r\nBcc: x@nhs.net", "domains": ["nhs.net"], "expect": "must not contain line breaks or control characters"},
 {"group": "control", "fn": "control", "name": "a line feed in a subject", "text": "Subject\n", "expect": "must not contain line breaks or control characters"},
 {"group": "control", "fn": "control", "name": "a tab", "text": "x\t", "expect": "must not contain line breaks or control characters"},
 {"group": "control", "fn": "control", "name": "the drafted subject's shape", "text": "Shutter C-000012: manual check needed, Downstream Out, encounter ENC-1015", "expect": ""},
 {"group": "bare", "name": "a display name", "text": "Team <a@nhs.net>", "domains": ["nhs.net"], "expect": "must be a bare address, local@domain, with no display name, brackets or spaces"},
 {"group": "bare", "name": "a space inside", "text": "a b@nhs.net", "domains": ["nhs.net"], "expect": "must be a bare address, local@domain, with no display name, brackets or spaces"},
 {"group": "bare", "name": "a quoted local part", "text": "\"a\"@nhs.net", "domains": ["nhs.net"], "expect": "must be a bare address, local@domain, with no display name, brackets or spaces"},
 {"group": "bare", "name": "an empty local part", "text": "@nhs.net", "domains": ["nhs.net"], "expect": "must be an address"},
 {"group": "bare", "fn": "addresses", "name": "the second of a list is outside", "text": " a@nhs.net , b@evil.com", "domains": ["nhs.net"], "expect": "b@evil.com: not in the allowed domains"},
 {"group": "bare", "fn": "addresses", "name": "a list inside the domains", "text": "a@nhs.net, b@nhs.net", "domains": ["nhs.net"], "expect": ""},
 {"group": "bare", "fn": "addresses", "name": "an empty list is the caller's question", "text": "", "domains": ["nhs.net"], "expect": ""},
 {"group": "domains", "fn": "domain", "name": "a domain name", "text": "example.nhs.uk", "expect": ""},
 {"group": "domains", "fn": "domain", "name": "an @ in the entry", "text": "@nhs.net", "expect": "must be a domain name such as example.nhs.uk (letters, digits, hyphens and dots)"},
 {"group": "domains", "fn": "domain", "name": "a space in the entry", "text": " x", "expect": "must be a domain name such as example.nhs.uk (letters, digits, hyphens and dots)"},
 {"group": "domains", "fn": "domain", "name": "a trailing dot", "text": "nhs.net.", "expect": "must be a domain name such as example.nhs.uk (letters, digits, hyphens and dots)"},
 {"group": "domains", "fn": "domain", "name": "a leading dot", "text": ".nhs.net", "expect": "must be a domain name such as example.nhs.uk (letters, digits, hyphens and dots)"},
 {"group": "domains", "fn": "domain", "name": "a leading hyphen", "text": "-x.net", "expect": "must be a domain name such as example.nhs.uk (letters, digits, hyphens and dots)"},
 {"group": "domains", "fn": "domain", "name": "an empty label", "text": "a..b", "expect": "must be a domain name such as example.nhs.uk (letters, digits, hyphens and dots)"},
 {"group": "domains", "fn": "domain", "name": "one label alone, the default sender's", "text": "localhost", "expect": ""},
 {"group": "domains", "fn": "domain", "name": "upper case", "text": "NHS.NET", "expect": ""}
]
}

}
