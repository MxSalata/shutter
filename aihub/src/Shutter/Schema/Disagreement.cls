/// A specialist's view the coordinator did not follow, kept in the plan rather than smoothed over.
Class Shutter.Schema.Disagreement Extends (%RegisteredObject, %JSON.Adaptor)
{

/// The board member's code: conformance, encounter or impact.
Property Member As %String(%JSONFIELDNAME = "member", MAXLEN = 32) [ Required ];

/// The disposition that member proposed.
Property Said As %String(%JSONFIELDNAME = "said", MAXLEN = 1000) [ Required ];

/// Why the plan does not follow it.
Property WhyKept As %String(%JSONFIELDNAME = "why_kept", MAXLEN = 1000) [ Required ];

}
