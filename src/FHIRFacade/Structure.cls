/// The structural checks IRIS for Health's FHIR server makes on a body before it stores it, without a profile and
/// without Java, as they were probed on 2027.1.0AI Build 109U on 8 Nov 2026: unknown elements at every level, required
/// elements, a single value given as an array or an array as a single value, an object where a primitive belongs and the
/// reverse, nulls and empty strings, empty objects and arrays, JSON types, the forms of <code>code</code>,
/// <code>id</code>, <code>date</code>, <code>dateTime</code> and <code>instant</code>, and the codes of required bindings.
/// Every problem is listed, in the order IRIS lists them: the body's members in order, depth first, then the missing
/// required elements of each object in alphabetical order.
/// <p>Its reach: Encounter, Patient and Location, their elements as R4 defines them, and inside them the data types the
/// demo and Shutter write (<code>Encounter.location</code>, Identifier, Reference, Coding, CodeableConcept, Period, Meta,
/// HumanName, Extension, Duration) and contained resources of the three types. Other complex elements
/// (<code>text</code>, <code>telecom</code>, <code>address</code>, <code>participant</code>, <code>Patient.link</code>
/// and the like) are checked for their shape only, and the value of an extension is not checked: IRIS checks more there
/// than this class does.</p>
Class FHIRFacade.Structure
{

Parameter CODE = "[^\s]+(\s[^\s]+)*";

Parameter ID = "[A-Za-z0-9\-\.]{1,64}";

Parameter DATE = "([0-9]([0-9]([0-9][1-9]|[1-9]0)|[1-9]00)|[1-9]000)(-(0[1-9]|1[0-2])(-(0[1-9]|[1-2][0-9]|3[0-1]))?)?";

Parameter DATETIME = "([0-9]([0-9]([0-9][1-9]|[1-9]0)|[1-9]00)|[1-9]000)(-(0[1-9]|1[0-2])(-(0[1-9]|[1-2][0-9]|3[0-1])(T([01][0-9]|2[0-3]):[0-5][0-9]:([0-5][0-9]|60)(\.[0-9]+)?(Z|(\+|-)((0[0-9]|1[0-3]):[0-5][0-9]|14:00)))?)?)?";

Parameter INSTANT = "([0-9]([0-9]([0-9][1-9]|[1-9]0)|[1-9]00)|[1-9]000)-(0[1-9]|1[0-2])-(0[1-9]|[1-2][0-9]|3[0-1])T([01][0-9]|2[0-3]):[0-5][0-9]:([0-5][0-9]|60)(\.[0-9]+)?(Z|(\+|-)((0[0-9]|1[0-3]):[0-5][0-9]|14:00))";

/// The elements of a resource (R4 Resource and DomainResource), each <code>name|cardinality|type|codes</code>, where the
/// cardinality is 1 (required), ? (optional) or * (an array) and a type of - is checked for its shape only.
Parameter RESOURCE = "id|?|id;meta|?|Meta;implicitRules|?|uri;language|?|code;text|?|-;contained|*|Resource;extension|*|Extension;modifierExtension|*|Extension";

Parameter ELEMENT = "id|?|string;extension|*|Extension";

/// One resource checked: the OperationOutcome text that lists every problem, or "" when there is none.
ClassMethod Check(type As %String, resource As %DynamicObject) As %String
{
    Set issues = []
    Do ..Object(resource, type, type, issues)
    Quit:issues.%Size()=0 ""
    Quit ##class(FHIRFacade.Outcome).Issues(issues)
}

/// The elements a type has, in <var>spec</var>(name) = <code>$LISTBUILD(cardinality, type, codes)</code>.
ClassMethod Load(type As %String, Output spec)
{
    Kill spec
    Set text = ..Spec(type)
    Quit:text=""
    For i = 1:1:$LENGTH(text, ";") {
        Set one = $PIECE(text, ";", i)
        Set spec($PIECE(one, "|", 1)) = $LISTBUILD($PIECE(one, "|", 2), $PIECE(one, "|", 3), $PIECE(one, "|", 4))
    }
}

/// The elements of <var>type</var> as <code>name|cardinality|type|codes</code> separated by ";", or "".
ClassMethod Spec(type As %String) As %String
{
    Quit:type="Encounter" ..#RESOURCE _ ";identifier|*|Identifier;status|1|code|arrived,cancelled,entered-in-error,finished,in-progress,onleave,planned,triaged,unknown;statusHistory|*|-;class|1|Coding;classHistory|*|-;type|*|CodeableConcept;serviceType|?|CodeableConcept;priority|?|CodeableConcept;subject|?|Reference;episodeOfCare|*|Reference;basedOn|*|Reference;participant|*|-;appointment|*|Reference;period|?|Period;length|?|Duration;reasonCode|*|CodeableConcept;reasonReference|*|Reference;diagnosis|*|-;account|*|Reference;hospitalization|?|-;location|*|Encounter.location;serviceProvider|?|Reference;partOf|?|Reference"
    Quit:type="Patient" ..#RESOURCE _ ";identifier|*|Identifier;active|?|boolean;name|*|HumanName;telecom|*|-;gender|?|code|female,male,other,unknown;birthDate|?|date;deceasedBoolean|?|boolean;deceasedDateTime|?|dateTime;address|*|-;maritalStatus|?|CodeableConcept;multipleBirthBoolean|?|boolean;multipleBirthInteger|?|integer;photo|*|-;contact|*|-;communication|*|-;generalPractitioner|*|Reference;managingOrganization|?|Reference;link|*|-"
    Quit:type="Location" ..#RESOURCE _ ";identifier|*|Identifier;status|?|code|active,inactive,suspended;operationalStatus|?|Coding;name|?|string;alias|*|string;description|?|string;mode|?|code|instance,kind;type|*|CodeableConcept;telecom|*|-;address|?|-;physicalType|?|CodeableConcept;position|?|-;managingOrganization|?|Reference;partOf|?|Reference;hoursOfOperation|*|-;availabilityExceptions|?|string;endpoint|*|Reference"
    Quit:type="Encounter.location" ..#ELEMENT _ ";modifierExtension|*|Extension;location|1|Reference;status|?|code|active,completed,planned,reserved;physicalType|?|CodeableConcept;period|?|Period"
    Quit:type="Identifier" ..#ELEMENT _ ";use|?|code|official,old,secondary,temp,usual;type|?|CodeableConcept;system|?|uri;value|?|string;period|?|Period;assigner|?|Reference"
    Quit:type="Reference" ..#ELEMENT _ ";reference|?|string;type|?|uri;identifier|?|Identifier;display|?|string"
    Quit:type="Coding" ..#ELEMENT _ ";system|?|uri;version|?|string;code|?|code;display|?|string;userSelected|?|boolean"
    Quit:type="CodeableConcept" ..#ELEMENT _ ";coding|*|Coding;text|?|string"
    Quit:type="Period" ..#ELEMENT _ ";start|?|dateTime;end|?|dateTime"
    Quit:type="Meta" ..#ELEMENT _ ";versionId|?|id;lastUpdated|?|instant;source|?|uri;profile|*|canonical;security|*|Coding;tag|*|Coding"
    Quit:type="HumanName" ..#ELEMENT _ ";use|?|code|anonymous,maiden,nickname,official,old,temp,usual;text|?|string;family|?|string;given|*|string;prefix|*|string;suffix|*|string;period|?|Period"
    Quit:type="Extension" ..#ELEMENT _ ";url|1|uri"
    Quit:type="Duration" ..#ELEMENT _ ";value|?|decimal;comparator|?|code;unit|?|string;system|?|uri;code|?|code"
    Quit ""
}

/// Checks one object of type <var>type</var> found at <var>path</var>, adding its problems to <var>issues</var>.
ClassMethod Object(object As %DynamicObject, type As %String, path As %String, issues As %DynamicArray)
{
    Do ..Load(type, .spec)
    Set resource = $CASE(type, "Encounter": 1, "Patient": 1, "Location": 1, : 0)
    Set iter = object.%GetIterator()
    While iter.%GetNext(.key) {
        Continue:resource&&(key="resourceType")
        // A primitive's extension sibling, _name, belongs to the element name.
        Continue:($EXTRACT(key)="_")&&..Known(.spec, $EXTRACT(key, 2, *))
        // An extension's value[x].
        Continue:(type="Extension")&&($EXTRACT(key, 1, 5)="value")&&($EXTRACT(key, 6)?1U)
        If '..Known(.spec, key) {
            Do issues.%Push(..Issue("UnexpectedPropertyName", "The property name '" _ key _ "' is not valid for type '" _ type _ "'", path))
            Continue
        }
        Set card = $LISTGET(spec(key), 1), kind = $LISTGET(spec(key), 2), codes = $LISTGET(spec(key), 3)
        Set at = path _ "." _ key, json = object.%GetTypeOf(key)
        If card '= "*" {
            If json = "array" {
                Do issues.%Push(..Issue("UnexpectedArray", "Property '" _ key _ "' of Type '" _ type _ "' cannot be an Array", at))
            } Else {
                Do ..Value(object, key, key, type, kind, codes, at, issues)
            }
            Continue
        }
        If json = "null" {
            Do issues.%Push(..Issue("EmptyValue", "Property '" _ key _ "' of Type '" _ type _ "' cannot be null or an empty string.", at))
            Continue
        }
        If json '= "array" {
            Do issues.%Push(..Issue("NotAnArray", "Property '" _ key _ "' of Type '" _ type _ "' must be an Array", at))
            Continue
        }
        Set list = object.%Get(key)
        If list.%Size() = 0 {
            Do issues.%Push(..Issue("EmptyObjectOrArray", "Property '" _ key _ "' of Type '" _ type _ "' cannot be an empty object or array.", at))
            Continue
        }
        For i = 0:1:list.%Size() - 1 {
            Do ..Value(list, i, key, type, kind, codes, at _ "[" _ i _ "]", issues)
        }
    }
    Set name = ""
    For {
        Set name = $ORDER(spec(name))
        Quit:name=""
        Continue:$LISTGET(spec(name), 1)'="1"
        Continue:..Present(object, name)
        Do issues.%Push(..Issue("MissingRequiredProperty", "The type '" _ type _ "' requires a property named '" _ name _ "'", path))
    }
}

/// Checks one value: <var>container</var>.%Get(<var>key</var>), of the element <var>property</var> of
/// <var>owner</var>, whose type is <var>kind</var>, at <var>at</var>.
ClassMethod Value(container, key, property As %String, owner As %String, kind As %String, codes As %String, at As %String, issues As %DynamicArray)
{
    Set json = container.%GetTypeOf(key), named = "Property '" _ property _ "' of Type '" _ owner _ "'"
    If (json = "null") || ((json = "string") && (container.%Get(key) = "")) {
        Do issues.%Push(..Issue("EmptyValue", named _ " cannot be null or an empty string.", at))
        Quit
    }
    If ..Primitive(kind) {
        If json = "object" {
            Do issues.%Push(..Issue("UnexpectedObject", named _ " cannot be an Object", at))
            Quit
        }
        If json = "array" {
            Do issues.%Push(..Issue("UnexpectedArray", named _ " cannot be an Array", at))
            Quit
        }
        Set want = $CASE(kind, "boolean": "boolean", "integer": "number", "positiveInt": "number", "unsignedInt": "number", "decimal": "number", : "string")
        Do:json'=want issues.%Push(..Issue("WrongJsonType", named _ " is type " _ json _ " but must be " _ want, at))
        Set text = container.%Get(key)
        Set pattern = $CASE(kind, "code": ..#CODE, "id": ..#ID, "date": ..#DATE, "dateTime": ..#DATETIME, "instant": ..#INSTANT, : "")
        If (pattern '= "") && '$MATCH(text, pattern) {
            Do issues.%Push(..Issue("MalformedValue", "The value '" _ text _ "' of " _ named _ " is a malformed '" _ kind _ "'. It should match the Regex '" _ pattern _ "'", at))
        }
        If (codes '= "") && '$LISTFIND($LISTFROMSTRING(codes), text) {
            Do issues.%Push(..Issue("ValueNotInEnumeration", "The value '" _ text _ "' of " _ named _ " must be one of (" _ codes _ ")", at))
        }
        Quit
    }
    If json = "array" {
        Do issues.%Push(..Issue("UnexpectedArray", named _ " cannot be an Array", at))
        Quit
    }
    If json '= "object" {
        Do issues.%Push(..Issue("NotAnObject", named _ " must be an Object", at))
        Quit
    }
    Set object = container.%Get(key)
    If 'object.%GetIterator().%GetNext() {
        Do issues.%Push(..Issue("EmptyObjectOrArray", named _ " cannot be an empty object or array.", at))
        Quit
    }
    If kind = "Resource" {
        // A contained resource of one of the three types is checked as that type.
        Set type = object.%Get("resourceType")
        Do:$CASE(type, "Encounter": 1, "Patient": 1, "Location": 1, : 0) ..Object(object, type, at, issues)
        Quit
    }
    Do:kind'="-" ..Object(object, kind, at, issues)
}

/// Whether <var>name</var> is one of the elements in <var>spec</var>: a whole name, compared exactly.
ClassMethod Known(ByRef spec, name As %String) As %Boolean
{
    Quit:(name="")||($LENGTH(name)>255) 0
    Quit ''$DATA(spec(name))
}

/// Whether an element counts as given: not null, not an empty string, not an empty object or array.
ClassMethod Present(object As %DynamicObject, name As %String) As %Boolean
{
    Quit:'object.%IsDefined(name) 0
    Set json = object.%GetTypeOf(name)
    Quit:json="null" 0
    Quit:(json="string")&&(object.%Get(name)="") 0
    If (json = "object") || (json = "array") {
        Quit object.%Get(name).%GetIterator().%GetNext()
    }
    Quit 1
}

ClassMethod Primitive(kind As %String) As %Boolean
{
    Quit $CASE(kind, "boolean": 1, "integer": 1, "positiveInt": 1, "unsignedInt": 1, "decimal": 1, "string": 1, "code": 1, "id": 1, "uri": 1, "url": 1, "canonical": 1, "markdown": 1, "date": 1, "dateTime": 1, "instant": 1, "time": 1, : 0)
}

ClassMethod Issue(name As %String, text As %String, expression As %String) As %DynamicObject
{
    Quit {"severity": "error", "code": "invalid", "diagnostics": ("<HSFHIRErr>" _ name), "details": {"text": (text)}, "expression": [(expression)]}
}

}
