# usage: fake_receiver.py PORT WORKDIR SECONDS: an MLLP receiver that records exactly what reached it, for pathology_check.py.
# Every frame goes to WORKDIR/rx-PORT.jsonl, one JSON object a line: the time, the connection's number, the control id, the
# frame's bytes in hex (without the MLLP wrapper), which copy of that control id this is (1 the first, kept across restarts)
# and what was answered. Connections that send nothing are counted in
# WORKDIR/conns-PORT, so a read-only probe of the listener is no send. It answers by WORKDIR/mode-PORT, JSON read afresh for
# each frame:
#   default      the code for anything not named below: AA, CA, AE, CE, AR, CR or SILENT (read, never answer). Default AA.
#   words        the text for MSA-3 with the default code.
#   by_control   {control id: {"code": ..., "words": ...}}
#   ae_nonascii  {"words": ...}: AE for a frame holding a byte above 0x7F.
#   ae_unknown_code  {"known": [...], "words": ...}: AE for a frame with an OBX-3 code not in known; MSA-3 is words then that code.
#   reset_on_connect  true: accepts a connection and resets it before reading, so no frame is ever heard.
#   held         {"controls": [...], "words": ...}: this receiver already holds these messages and refuses them.
#   refuses_repeat  {"words": ...}: AE, in those words, to a second copy of a control id it has already heard.
#   delay        seconds to wait before each answer, so a drain takes a while.
#   die_after    close everything and exit once this many frames have come in since it started.
# It stops when WORKDIR/stop-PORT exists or after SECONDS.
import json
import os
import socket
import struct
import sys
import time

port, workdir, seconds = int(sys.argv[1]), sys.argv[2], float(sys.argv[3])
stop = os.path.join(workdir, f"stop-{port}")
mode_file = os.path.join(workdir, f"mode-{port}")
conns_file = os.path.join(workdir, f"conns-{port}")
if os.path.exists(stop):
    os.remove(stop)


def spec():
    try:
        with open(mode_file) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def unknown_code(known, frame):
    for seg in frame.split(b"\r"):
        if seg.startswith(b"OBX|"):
            fields = seg.decode("latin-1").split("|")
            code = fields[3].split("^")[0] if len(fields) > 3 else ""
            if code not in known:
                return code
    return ""


def answer_for(mode, ctl, frame, seen=0):
    by = (mode.get("by_control") or {}).get(ctl)
    if by:
        return by.get("code", "AA"), by.get("words", "")
    if mode.get("refuses_repeat") and seen:
        return "AE", mode["refuses_repeat"].get("words", "")
    held = mode.get("held") or {}
    if ctl in (held.get("controls") or []):
        return "AE", held.get("words", "")
    unknown = mode.get("ae_unknown_code")
    if unknown:
        code = unknown_code(unknown.get("known") or [], frame)
        if code:
            return "AE", unknown.get("words", "") + code
    nonascii = mode.get("ae_nonascii")
    if nonascii and any(b > 0x7F for b in frame):
        return "AE", nonascii.get("words", "")
    return mode.get("default", "AA"), mode.get("words", "")


def ack(ctl, code, words):
    text = f"MSH|^~\\&|RX|HOSP|TX|HOSP|20261105000000||ACK|A{ctl}|P|2.5.1\rMSA|{code}|{ctl}|{words}\r"
    return b"\x0b" + text.encode("latin-1") + b"\x1c\r"


def main():
    end = time.time() + seconds
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(16)
    server.settimeout(0.1)
    conns, opened, heard = [], 0, 0
    copies = {}
    if os.path.exists(os.path.join(workdir, f"rx-{port}.jsonl")):
        with open(os.path.join(workdir, f"rx-{port}.jsonl")) as earlier:
            for line in earlier:
                if line.strip():
                    was = json.loads(line)["ctl"]
                    copies[was] = copies.get(was, 0) + 1
    with open(os.path.join(workdir, f"rx-{port}.jsonl"), "a", buffering=1) as log:
        while time.time() < end and not os.path.exists(stop):
            try:
                c, _ = server.accept()
                c.settimeout(0.05)
                opened += 1
                with open(conns_file, "w") as f:
                    f.write(str(opened))
                if spec().get("reset_on_connect"):
                    c.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
                    c.close()
                else:
                    conns.append([c, b"", opened])
            except socket.timeout:
                pass
            for p in list(conns):
                try:
                    data = p[0].recv(65536)
                except socket.timeout:
                    continue
                except OSError:
                    conns.remove(p)
                    continue
                if not data:
                    p[0].close()
                    conns.remove(p)
                    continue
                p[1] += data
                while b"\x1c\r" in p[1]:
                    raw, p[1] = p[1].split(b"\x1c\r", 1)
                    frame = raw[raw.find(b"\x0b") + 1:]
                    ctl = frame.split(b"\r")[0].decode("latin-1").split("|")[9]
                    mode = spec()
                    code, words = answer_for(mode, ctl, frame, copies.get(ctl, 0))
                    copies[ctl] = copies.get(ctl, 0) + 1
                    log.write(json.dumps({"t": round(time.time(), 3), "conn": p[2], "ctl": ctl, "hex": frame.hex(), "copy": copies[ctl], "answer": code}) + "\n")
                    heard += 1
                    if mode.get("delay"):
                        time.sleep(float(mode["delay"]))
                    if code != "SILENT":
                        p[0].sendall(ack(ctl, code, words))
                    if mode.get("die_after") and heard >= int(mode["die_after"]):
                        time.sleep(0.2)
                        for q in conns:
                            q[0].close()
                        server.close()
                        return
    for q in conns:
        q[0].close()
    server.close()


main()
