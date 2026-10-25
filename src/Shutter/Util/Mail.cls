/// The rules for the addresses and header text of an escalation email (CONTRACTS 10), as pure functions that read no
/// profile: the site profile's validator, the escalation routes, the escalation store and the mail operation all check
/// through them, so the same address passes or fails everywhere. A recipient is one bare address, local@domain, with
/// exactly one @, no display name, brackets or spaces, no line break or other control character, and a domain equal
/// to one of the site's allowed mail domains or a subdomain of one, compared without regard to case. An empty list of
/// allowed domains allows no address: a site names its domains before any email with patient identifiers leaves.
Class Shutter.Util.Mail Extends %RegisteredObject
{

/// "" when the text has no control character, else why it is refused. $ZSTRIP's C class covers $CHAR(0) to $CHAR(31),
/// so tab, CR and LF, and $CHAR(127) to $CHAR(159): nothing that could end a header line or start another passes.
ClassMethod ControlProblem(text As %String) As %String
{
    If $ZSTRIP(text, "*C") '= text Quit "must not contain line breaks or control characters"
    Quit ""
}

/// "" when the text is a domain name (labels of letters, digits and inner hyphens joined by dots, no leading or
/// trailing dot, at most 253 characters; one label alone is allowed, so "localhost" passes), else why it is refused.
/// The case is ignored; whitespace is not stripped, so " x" and "nhs.net " are refused.
ClassMethod DomainProblem(domain As %String) As %String
{
    Set d = $ZCONVERT(domain, "L")
    If (d '= "") && ($LENGTH(d) <= 253) && $MATCH(d, "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$") Quit ""
    Quit "must be a domain name such as example.nhs.uk (letters, digits, hyphens and dots)"
}

/// "" when the text is one bare address, local@domain, else why it is refused: a control character, not exactly one
/// @, whitespace or a display name's characters (< > , ; " ( ) [ ] \), an empty local part or domain, or a domain that
/// is not a domain name (a@nhs.net. and a@nhs..net are refused here).
ClassMethod ShapeProblem(address As %String) As %String
{
    Set problem = ..ControlProblem(address)
    If problem '= "" Quit problem
    If $LENGTH(address, "@") '= 2 Quit "must be one address with one @"
    If ($ZSTRIP(address, "*W") '= address) || ($TRANSLATE(address, "<>,;""()[]\", "") '= address) Quit "must be a bare address, local@domain, with no display name, brackets or spaces"
    If ($PIECE(address, "@", 1) = "") || ($PIECE(address, "@", 2) = "") Quit "must be an address"
    If ..DomainProblem($PIECE(address, "@", 2)) '= "" Quit "the domain is not a valid domain name"
    Quit ""
}

/// The allowed domains of a profile's mail.allowed_domains as a $LIST: each entry lowercased and stripped of
/// surrounding whitespace, empty entries and anything that is not an array left out.
ClassMethod Domains(list As %DynamicArray) As %List
{
    Set out = ""
    If '$ISOBJECT(list) || 'list.%IsA("%DynamicArray") Quit out
    Set it = list.%GetIterator()
    While it.%GetNext(.j, .d) {
        Continue:$ISOBJECT(d)
        Set d = $ZCONVERT($ZSTRIP(d, "<>W"), "L")
        If d '= "" Set out = out _ $LISTBUILD(d)
    }
    Quit out
}

/// Whether a domain is one of the allowed domains or a subdomain of one (trust.nhs.net under nhs.net), ignoring case.
ClassMethod DomainAllowed(domain As %String, domains As %List) As %Boolean
{
    Set domain = $ZCONVERT(domain, "L")
    For i = 1:1:$LISTLENGTH(domains) {
        Set d = $LIST(domains, i)
        If (domain = d) || ($EXTRACT(domain, * - $LENGTH(d), *) = ("." _ d)) Return 1
    }
    Quit 0
}

/// "" when the address is one bare address inside the allowed domains, else why it is refused. An empty list of
/// domains allows no address.
ClassMethod AddressProblem(address As %String, domains As %List) As %String
{
    Set problem = ..ShapeProblem(address)
    If problem '= "" Quit problem
    If $LISTLENGTH(domains) = 0 Quit "no allowed mail domains are set in the site profile (mail.allowed_domains)"
    If '..DomainAllowed($PIECE(address, "@", 2), domains) Quit "not in the allowed domains"
    Quit ""
}

/// The problem with a list of addresses a person typed (comma separated), against the allowed domains: "" when every
/// address passes AddressProblem, else the first offending address and why ("<address>: <problem>"). A control
/// character anywhere in the list refuses it whole. An empty list is "" (whether one is needed is the caller's question).
ClassMethod AddressesProblem(list As %String, domains As %List) As %String
{
    Set problem = ..ControlProblem(list)
    If problem '= "" Quit problem
    For i = 1:1:$LENGTH(list, ",") {
        Set a = $ZSTRIP($PIECE(list, ",", i), "<>W")
        Continue:a=""
        Set problem = ..AddressProblem(a, domains)
        If problem '= "" Return a _ ": " _ problem
    }
    Quit ""
}

/// The text as one header line's value: tab, CR and LF become spaces and every other control character is removed,
/// so no value can end its header or start another. The last defence of the .eml writer and the SMTP message, behind
/// the checks above.
ClassMethod HeaderValue(text As %String) As %String
{
    Quit $ZSTRIP($TRANSLATE(text, $CHAR(9, 10, 13), "   "), "*C")
}

}
