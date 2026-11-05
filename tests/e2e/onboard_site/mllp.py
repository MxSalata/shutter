# usage: mllp.py PORT FILE... : sends each file over MLLP and prints the ACK's MSA. Run inside the container. MLLP_WAIT: seconds to wait for it.
import os, socket, sys, time
wait = float(os.environ.get('MLLP_WAIT', 20))
port = int(sys.argv[1])
for f in sys.argv[2:]:
    data = open(f, 'rb').read().replace(b'\n', b'\r')
    s = socket.create_connection(('127.0.0.1', port), timeout=20)
    s.sendall(b'\x0b' + data + b'\x1c\r')
    s.settimeout(wait)
    buf = b''
    try:
        while b'\x1c\r' not in buf:
            d = s.recv(65536)
            if not d:
                break
            buf += d
    except Exception as e:
        print('no ack', e)
    s.close()
    time.sleep(2)
    seg = [x for x in buf.strip(b'\x0b\x1c\r').split(b'\r') if x.startswith(b'MSA')]
    print(f, len(data), 'bytes', seg[0].decode() if seg else 'no MSA')
