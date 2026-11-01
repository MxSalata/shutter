package shutter.pex;

import ca.uhn.hl7v2.DefaultHapiContext;
import ca.uhn.hl7v2.ErrorCode;
import ca.uhn.hl7v2.HL7Exception;
import ca.uhn.hl7v2.HapiContext;
import ca.uhn.hl7v2.Location;
import ca.uhn.hl7v2.Version;
import ca.uhn.hl7v2.model.Group;
import ca.uhn.hl7v2.model.Message;
import ca.uhn.hl7v2.model.Segment;
import ca.uhn.hl7v2.model.Structure;
import ca.uhn.hl7v2.model.Type;
import ca.uhn.hl7v2.parser.CanonicalModelClassFactory;
import ca.uhn.hl7v2.parser.PipeParser;
import ca.uhn.hl7v2.parser.UnexpectedSegmentBehaviourEnum;
import ca.uhn.hl7v2.validation.impl.ValidationContextFactory;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * A second opinion on an HL7 v2 message from an independent parser (HAPI), for Shutter's evidence when IRIS cannot read a
 * message (docs/CONTRACTS.md, section 6.7): is the message well-formed and merely of a schema the site has not loaded, or
 * malformed, and where. Pure: a string in, a JSON report out, no IRIS calls, so it runs from the PEX operation and from
 * the Java gateway alike. Every message is read with the 2.5.1 structures (HAPI's canonical model), whatever version it
 * declares, so a 2.3.1 or 2.4 message and a site category such as MYSITE_2.5.1 are read too; the report says both.
 */
public final class Hl7Report {

    public static final String HAPI_VERSION = "2.6.0";
    public static final String CANONICAL = "2.5.1";
    public static final String PARSER = "HAPI " + HAPI_VERSION + " (Java, PEX)";

    private static final Pattern VERSION = Pattern.compile("(2\\.[1-9](?:\\.[0-9])?)");

    private Hl7Report() {
    }

    /** The report as JSON (see the class comment). Never throws: a failure is a report with parsed false. */
    public static String report(String raw) {
        StringBuilder out = new StringBuilder(2048);
        List<String> notes = new ArrayList<>();
        out.append("{\"parser\":").append(q(PARSER));
        String text = raw == null ? "" : raw.replace("\r\n", "\r").replace('\n', '\r').trim();
        if (text.isEmpty()) {
            out.append(",\"parsed\":false,\"valid\":false,\"errors\":[{\"code\":\"EMPTY\",\"message\":\"The message is empty\"}],\"segments\":[],\"segments_declared\":[],\"notes\":[]}");
            return out.toString();
        }
        String[] lines = text.split("\r");
        List<String> declared = new ArrayList<>();
        List<String> custom = new ArrayList<>();
        for (String line : lines) {
            if (line.length() >= 3) {
                String name = line.substring(0, 3);
                declared.add(name);
                if (name.startsWith("Z") && !custom.contains(name)) custom.add(name);
            }
        }
        if (!custom.isEmpty()) {
            notes.add("Site-defined segment(s) " + String.join(", ", custom) + " kept: a Z segment is the site's own by the standard, not an error");
        }
        String declaredVersion = mshField(lines[0], 12);
        String messageType = mshField(lines[0], 9);
        String controlId = mshField(lines[0], 10);
        boolean known = declaredVersion.length() > 0 && Version.supportsVersion(declaredVersion);
        String readAs = CANONICAL;
        if (!known) {
            Matcher m = VERSION.matcher(declaredVersion);
            if (m.find()) {
                notes.add("The declared version " + declaredVersion + " is not a standard HL7 version; it contains " + m.group(1) + ", so the message was read as a " + m.group(1) + " message with the 2.5.1 structures");
            } else if (declaredVersion.isEmpty()) {
                notes.add("MSH-12 names no version; the message was read with the 2.5.1 structures");
            } else {
                notes.add("The declared version " + declaredVersion + " is not a standard HL7 version; the message was read with the 2.5.1 structures");
            }
        }
        out.append(",\"declared_version\":").append(q(declaredVersion));
        out.append(",\"version_known\":").append(known);
        out.append(",\"read_as\":").append(q(readAs));
        out.append(",\"message_type\":").append(q(messageType));
        out.append(",\"control_id\":").append(q(controlId));

        // The text HAPI parses: an unknown version is replaced by the canonical one, since HAPI refuses versions it does not know.
        String toParse = known ? text : withMshField(lines, 12, CANONICAL);

        HapiContext ctx = new DefaultHapiContext();
        ctx.setModelClassFactory(new CanonicalModelClassFactory(CANONICAL));
        List<String> errors = new ArrayList<>();
        Message strict = null;
        boolean valid = false;
        try {
            // Strict: the default rules on the values, and a segment the structure does not expect there is an error, as
            // IRIS's own structural validation treats it; a site's Z segments are kept in place, since the standard gives
            // them to the site. A required segment with nothing in it is an error too (HAPI alone would let it pass).
            ctx.setValidationContext(ValidationContextFactory.defaultValidation());
            ctx.getParserConfiguration().setUnexpectedSegmentBehaviour(custom.isEmpty() ? UnexpectedSegmentBehaviourEnum.THROW_HL7_EXCEPTION : UnexpectedSegmentBehaviourEnum.ADD_INLINE);
            PipeParser strictParser = ctx.getPipeParser();
            strict = strictParser.parse(toParse);
            List<String> missing = new ArrayList<>();
            requiredMissing(strict, missing);
            for (String name : missing) {
                errors.add("{\"code\":\"REQUIRED_SEGMENT_MISSING\",\"message\":" + q("Missing required segment " + name) + ",\"segment\":" + q(name) + "}");
            }
            if (!custom.isEmpty()) {
                // With the Z segments taken out, a strict pass still tells a stray standard segment from a known one.
                StringBuilder withoutZ = new StringBuilder();
                for (String line : toParse.split("\r")) {
                    if (!line.startsWith("Z")) {
                        if (withoutZ.length() > 0) withoutZ.append('\r');
                        withoutZ.append(line);
                    }
                }
                try {
                    ctx.getParserConfiguration().setUnexpectedSegmentBehaviour(UnexpectedSegmentBehaviourEnum.THROW_HL7_EXCEPTION);
                    ctx.getPipeParser().parse(withoutZ.toString());
                } catch (HL7Exception e) {
                    errors.add(error(e));
                }
            }
            valid = errors.isEmpty();
        } catch (HL7Exception e) {
            errors.add(error(e));
        } catch (RuntimeException e) {
            errors.add("{\"code\":\"PARSER_ERROR\",\"message\":" + q(String.valueOf(e)) + "}");
        }
        Message lenient = strict;
        if (lenient == null) {
            try {
                // Lenient: no rules, unexpected segments kept in place, to describe what is there.
                ctx.setValidationContext(ValidationContextFactory.noValidation());
                ctx.getParserConfiguration().setUnexpectedSegmentBehaviour(UnexpectedSegmentBehaviourEnum.ADD_INLINE);
                lenient = ctx.getPipeParser().parse(toParse);
                notes.add("Read without validation to describe the structure");
            } catch (HL7Exception e) {
                errors.add(error(e));
            } catch (RuntimeException e) {
                errors.add("{\"code\":\"PARSER_ERROR\",\"message\":" + q(String.valueOf(e)) + "}");
            }
        }
        out.append(",\"parsed\":").append(lenient != null);
        out.append(",\"valid\":").append(valid);
        out.append(",\"structure\":").append(q(lenient == null ? "" : lenient.getClass().getSimpleName()));
        out.append(",\"errors\":[").append(String.join(",", errors)).append("]");
        out.append(",\"segments\":[");
        if (lenient != null) {
            List<String> segs = new ArrayList<>();
            walk(lenient, segs);
            out.append(String.join(",", segs));
        }
        out.append("]");
        out.append(",\"custom_segments\":[");
        for (int i = 0; i < custom.size(); i++) {
            if (i > 0) out.append(',');
            out.append(q(custom.get(i)));
        }
        out.append("]");
        out.append(",\"segments_declared\":[");
        for (int i = 0; i < declared.size(); i++) {
            if (i > 0) out.append(',');
            out.append(q(declared.get(i)));
        }
        out.append("]");
        out.append(",\"notes\":[");
        for (int i = 0; i < notes.size(); i++) {
            if (i > 0) out.append(',');
            out.append(q(notes.get(i)));
        }
        out.append("]}");
        try {
            ctx.close();
        } catch (Exception ignored) {
            // nothing to release that matters
        }
        return out.toString();
    }

    /** The required segments and groups of the structure that carry nothing, by name, in order. */
    private static void requiredMissing(Group group, List<String> missing) {
        String[] names;
        try {
            names = group.getNames();
        } catch (RuntimeException e) {
            return;
        }
        for (String name : names) {
            try {
                Structure[] reps = group.getAll(name);
                boolean any = false;
                for (Structure s : reps) {
                    if (!s.isEmpty()) {
                        any = true;
                        if (s instanceof Group) requiredMissing((Group) s, missing);
                    }
                }
                if (!any && group.isRequired(name)) missing.add(name);
            } catch (HL7Exception ignored) {
                // a structure that cannot be read is not reported as missing
            }
        }
    }

    /** Each segment of the parsed message in order: its name, how many fields it has and how many carry a value. */
    private static void walk(Group group, List<String> segs) {
        String[] names;
        try {
            names = group.getNames();
        } catch (RuntimeException e) {
            return;
        }
        for (String name : names) {
            Structure[] reps;
            try {
                reps = group.getAll(name);
            } catch (HL7Exception e) {
                continue;
            }
            for (Structure s : reps) {
                if (s instanceof Segment) {
                    Segment seg = (Segment) s;
                    int fields = seg.numFields();
                    int populated = 0;
                    for (int i = 1; i <= fields; i++) {
                        try {
                            Type[] values = seg.getField(i);
                            for (Type v : values) {
                                if (!v.isEmpty()) {
                                    populated++;
                                    break;
                                }
                            }
                        } catch (HL7Exception ignored) {
                            // a field that cannot be read counts as empty
                        }
                    }
                    boolean present = populated > 0;
                    if (!present) {
                        try {
                            present = !seg.isEmpty();
                        } catch (HL7Exception ignored) {
                            present = false;
                        }
                    }
                    if (present) {
                        segs.add("{\"name\":" + q(seg.getName()) + ",\"fields\":" + fields + ",\"populated\":" + populated + "}");
                    }
                } else if (s instanceof Group) {
                    walk((Group) s, segs);
                }
            }
        }
    }

    private static String error(HL7Exception e) {
        StringBuilder b = new StringBuilder();
        ErrorCode code = e.getError();
        b.append("{\"code\":").append(q(code == null ? "HL7" : code.name()));
        b.append(",\"message\":").append(q(e.getMessage() == null ? String.valueOf(e) : e.getMessage()));
        Location loc = e.getLocation();
        if (loc != null) {
            b.append(",\"segment\":").append(q(loc.getSegmentName() == null ? "" : loc.getSegmentName()));
            b.append(",\"field\":").append(loc.getField());
            b.append(",\"component\":").append(loc.getComponent());
        }
        b.append('}');
        return b.toString();
    }

    /** Field n of an MSH line (MSH-1 is the separator itself, so MSH-9 is piece 9). */
    static String mshField(String msh, int n) {
        if (msh == null || msh.length() < 4 || !msh.startsWith("MSH")) return "";
        char sep = msh.charAt(3);
        String[] parts = msh.split(Pattern.quote(String.valueOf(sep)), -1);
        if (n - 1 >= parts.length) return "";
        if (n == 1) return String.valueOf(sep);
        return parts[n - 1];
    }

    private static String withMshField(String[] lines, int n, String value) {
        String msh = lines[0];
        char sep = msh.charAt(3);
        String[] parts = msh.split(Pattern.quote(String.valueOf(sep)), -1);
        if (n - 1 < parts.length) parts[n - 1] = value;
        StringBuilder b = new StringBuilder(String.join(String.valueOf(sep), parts));
        for (int i = 1; i < lines.length; i++) b.append('\r').append(lines[i]);
        return b.toString();
    }

    static String q(String s) {
        StringBuilder b = new StringBuilder(s.length() + 2);
        b.append('"');
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"': b.append("\\\""); break;
                case '\\': b.append("\\\\"); break;
                case '\n': b.append("\\n"); break;
                case '\r': b.append("\\r"); break;
                case '\t': b.append("\\t"); break;
                default:
                    if (c < 0x20) b.append(String.format("\\u%04x", (int) c)); else b.append(c);
            }
        }
        return b.append('"').toString();
    }

    /** A quick look from a shell: java -cp ... shutter.pex.Hl7Report < message.hl7 */
    public static void main(String[] args) throws Exception {
        byte[] bytes = System.in.readAllBytes();
        System.out.println(report(new String(bytes, java.nio.charset.StandardCharsets.UTF_8)));
    }
}
