#!/usr/bin/env python3
# usage: listener.py PORT WORKDIR SECONDS: a made-up MLLP receiver on the loopback address, for measuring. Standard library only.
#
# It answers by WORKDIR/mode-PORT, JSON read afresh for each frame, so a run can change its answers with no reconnect:
#   {"mode": "up"}                 answers AA.
#   {"mode": "answer", "code": "AE", "words": "...", "err": ["ERR|..."]}
#                                  answers that code (AA, AE, AR, CA, CE, CR), MSA-3 the words, then the ERR segments as written.
#                                  "by_control": {control id: {"code", "words", "err"}} overrides per message, and an unlisted
#                                  one takes the outer code, AA by default. "nonascii": {"code", "words", "err"} applies to a
#                                  frame holding a byte above 0x7F.
#   {"mode": "take_and_die"}       reads the frame, closes with no answer and exits, so the port then refuses. "after": N answers
#                                  AA to the first N-1 frames.
#   {"mode": "hang"}               accepts, reads and never answers.
#   {"mode": "noaccept"}           listens and never accepts. Read once, at the start.
#   {"mode": "log_hex"}            answers AA and writes each frame's bytes in the log. "hex": true does the same in any mode.
# "delay": seconds to wait before each answer, in any mode that answers, so a drain takes a while.
# Down is no process at all: stop this one and the port refuses the connect.
#
# Every event goes to WORKDIR/rx-PORT.jsonl, one JSON object a line, kept across restarts: {"event": "open", "conn"},
# {"event": "close", "conn", "frames"}, and {"event": "frame", "t", "conn", "ctl", "copy", "bytes", "sha1", "high", "answer"} with
# "hex" where asked for. "copy" is which copy of that control id this is, 1 the first; "answer" is the code sent, or NONE.
# It stops when WORKDIR/stop-PORT exists or after SECONDS.
import hashlib
import json
import os
import socket
import sys
import threading
import time

END_OF_FRAME = b"\x1c\r"


def read_spec(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def control_id(frame):
    fields = frame.split(b"\r")[0].decode("latin-1").split("|")
    return fields[9] if len(fields) > 9 else ""


def answer_for(spec, ctl, frame, heard):
    """(code or None for no answer, words, ERR segments, die afterwards) for this frame. heard counts frames, this one included."""
    mode = spec.get("mode", "up")
    if mode == "hang":
        return None, "", [], False
    if mode == "take_and_die":
        if heard >= int(spec.get("after", 1)):
            return None, "", [], True
        return "AA", "", [], False
    if mode == "answer":
        by = (spec.get("by_control") or {}).get(ctl)
        if by:
            return by.get("code", "AA"), by.get("words", ""), by.get("err", []), False
        high = spec.get("nonascii")
        if high and any(b > 0x7F for b in frame):
            return high.get("code", "AE"), high.get("words", ""), high.get("err", []), False
        return spec.get("code", "AA"), spec.get("words", ""), spec.get("err", []), False
    return "AA", "", [], False


def ack_bytes(ctl, code, words, err):
    segments = [f"MSH|^~\\&|RX|FAKELAB|TX|HOSP|20261106000000||ACK|A{ctl}|P|2.5.1", f"MSA|{code}|{ctl}|{words}"] + list(err)
    return b"\x0b" + "\r".join(segments).encode("latin-1") + b"\r" + END_OF_FRAME


class Listener:
    def __init__(self, port, workdir, seconds):
        self.port = port
        self.stop_file = os.path.join(workdir, f"stop-{port}")
        self.mode_file = os.path.join(workdir, f"mode-{port}")
        self.log_path = os.path.join(workdir, f"rx-{port}.jsonl")
        self.end = time.time() + seconds
        self.lock = threading.Lock()
        self.heard = 0
        self.copies = {}
        self.opened = 0
        if os.path.exists(self.stop_file):
            os.remove(self.stop_file)
        if os.path.exists(self.log_path):
            with open(self.log_path) as earlier:
                for line in earlier:
                    if line.strip():
                        was = json.loads(line)
                        if was.get("event") == "frame":
                            self.copies[was["ctl"]] = was["copy"]
                        elif was.get("event") == "open":
                            self.opened = was["conn"]
        self.log = open(self.log_path, "a", buffering=1)

    def done(self):
        return time.time() > self.end or os.path.exists(self.stop_file)

    def write(self, **row):
        with self.lock:
            self.log.write(json.dumps(row) + "\n")

    def on_frame(self, c, n, frame):
        spec = read_spec(self.mode_file)
        ctl = control_id(frame)
        with self.lock:
            self.heard += 1
            heard = self.heard
            self.copies[ctl] = self.copies.get(ctl, 0) + 1
            copy = self.copies[ctl]
        code, words, err, die = answer_for(spec, ctl, frame, heard)
        row = {"event": "frame", "t": round(time.time(), 3), "conn": n, "ctl": ctl, "copy": copy, "bytes": len(frame), "sha1": hashlib.sha1(frame).hexdigest()[:12], "high": " ".join(f"{b:02x}" for b in frame if b > 0x7F), "answer": code or "NONE"}
        if spec.get("mode") == "log_hex" or spec.get("hex"):
            row["hex"] = frame.hex()
        self.write(**row)
        if die:
            self.log.flush()
            c.close()
            os._exit(0)
        if code:
            if spec.get("delay"):
                time.sleep(float(spec["delay"]))
            try:
                c.sendall(ack_bytes(ctl, code, words, err))
            except OSError:
                pass

    def serve(self, c, n):
        buf = b""
        frames = 0
        c.settimeout(0.2)
        while not self.done():
            try:
                data = c.recv(65536)
            except socket.timeout:
                continue
            except OSError:
                break
            if not data:
                break
            buf += data
            while END_OF_FRAME in buf:
                raw, buf = buf.split(END_OF_FRAME, 1)
                frames += 1
                self.on_frame(c, n, raw[raw.find(b"\x0b") + 1:])
        self.write(event="close", conn=n, frames=frames)
        try:
            c.close()
        except OSError:
            pass

    def run(self):
        server = socket.socket()
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", self.port))
        server.listen(16)
        server.settimeout(0.2)
        if read_spec(self.mode_file).get("mode") == "noaccept":
            server.listen(1)
            while not self.done():
                time.sleep(0.2)
            server.close()
            return
        while not self.done():
            try:
                c, _ = server.accept()
            except socket.timeout:
                continue
            self.opened += 1
            self.write(event="open", conn=self.opened)
            threading.Thread(target=self.serve, args=(c, self.opened), daemon=True).start()
        server.close()
        time.sleep(0.3)


if __name__ == "__main__":
    Listener(int(sys.argv[1]), sys.argv[2], float(sys.argv[3])).run()
