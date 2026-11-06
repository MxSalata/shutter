# usage: mllp_send.py PORT FILE [WAIT]: sends the file's bytes unchanged over MLLP and prints the reply's MSA line. Run inside the container.
import socket
import sys
import time

port, path = int(sys.argv[1]), sys.argv[2]
wait = float(sys.argv[3]) if len(sys.argv) > 3 else 20
with open(path, "rb") as f:
    data = f.read()
# A stock service takes one connection at a time and its port is shut for a moment after each close, so a refusal here is
# the last send's shadow. Only the connect is retried: once the bytes have gone, nothing is sent again.
give_up = time.time() + 20
while True:
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=20)
        break
    except ConnectionRefusedError:
        if time.time() >= give_up:
            raise
        time.sleep(0.25)
s.sendall(b"\x0b" + data + b"\x1c\r")
s.settimeout(wait)
buf = b""
try:
    while b"\x1c\r" not in buf:
        d = s.recv(65536)
        if not d:
            break
        buf += d
except OSError as e:
    print("no ack", e)
s.close()
seg = [x for x in buf.strip(b"\x0b\x1c\r").split(b"\r") if x.startswith(b"MSA")]
print(seg[0].decode("latin-1") if seg else "no MSA")
