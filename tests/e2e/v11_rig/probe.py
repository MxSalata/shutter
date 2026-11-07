#!/usr/bin/env python3
# usage: probe.py PORT FILE [WAIT]: one connect and at most one frame, for checking a listener, run in the same place as it.
# Prints one line and retries nothing: REFUSED, TIMEOUT (connected, sent, no answer in WAIT seconds), CLOSED (the far end
# closed with no answer) or the reply's MSA line, then each ERR line. FILE "-" connects and sends nothing, and prints CONNECTED.
import socket
import sys

port, path = int(sys.argv[1]), sys.argv[2]
wait = float(sys.argv[3]) if len(sys.argv) > 3 else 5
s = socket.socket()
s.settimeout(wait)
try:
    s.connect(("127.0.0.1", port))
except ConnectionRefusedError:
    print("REFUSED")
    sys.exit(0)
if path == "-":
    print("CONNECTED")
    sys.exit(0)
with open(path, "rb") as f:
    s.sendall(b"\x0b" + f.read() + b"\x1c\r")
buf = b""
try:
    while b"\x1c\r" not in buf:
        d = s.recv(65536)
        if not d:
            print("CLOSED")
            sys.exit(0)
        buf += d
except socket.timeout:
    print("TIMEOUT")
    sys.exit(0)
except ConnectionResetError:
    print("CLOSED")
    sys.exit(0)
print(" ".join(x.decode("latin-1") for x in buf.strip(b"\x0b\x1c\r").split(b"\r") if x.startswith((b"MSA", b"ERR"))))
