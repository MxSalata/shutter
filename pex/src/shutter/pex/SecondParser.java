package shutter.pex;

import com.intersystems.enslib.pex.BusinessOperation;
import com.intersystems.jdbc.IRISObject;

/**
 * The Second Parser (docs/CONTRACTS.md, section 6.1): a PEX business operation in Shutter's production that answers a
 * Shutter.Msg.ParseRequest with a Shutter.Msg.ParseReport, the report of Hl7Report on the request's raw message. IRIS
 * sends it the message it could not read; the Visual Trace shows the request and the report like any other message.
 */
public class SecondParser extends BusinessOperation {

    @Override
    public void OnInit() throws Exception {
        LOGINFO("Second Parser ready: " + Hl7Report.PARSER);
    }

    @Override
    public void OnTearDown() throws Exception {
    }

    @Override
    public Object OnMessage(Object request) throws Exception {
        IRISObject req = (IRISObject) request;
        String raw = req.getString("Raw");
        String json = Hl7Report.report(raw);
        IRISObject report = (IRISObject) iris.classMethodObject("Shutter.Msg.ParseReport", "%New");
        report.set("ReportJSON", json);
        report.set("Parser", Hl7Report.PARSER);
        return report;
    }
}
