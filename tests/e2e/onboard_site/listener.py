# usage: listener.py PORT LOG [SECONDS]: an MLLP receiver answering AA to everything; writes each control id to LOG.
import socket, sys, time
port, path = int(sys.argv[1]), sys.argv[2]
end = time.time() + float(sys.argv[3] if len(sys.argv) > 3 else 1200)
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', port))
s.listen(5)
s.settimeout(1)
log = open(path, 'a', buffering=1)
conns = []
while time.time() < end:
    try:
        c, _ = s.accept()
        c.settimeout(0.2)
        conns.append([c, b''])
    except socket.timeout:
        pass
    for p in list(conns):
        try:
            d = p[0].recv(65536)
        except socket.timeout:
            continue
        except OSError:
            conns.remove(p)
            continue
        if not d:
            conns.remove(p)
            continue
        p[1] += d
        while b'\x1c\r' in p[1]:
            frame, p[1] = p[1].split(b'\x1c\r', 1)
            ctl = frame.lstrip(b'\x0b').split(b'\r')[0].decode('latin-1').split('|')[9]
            log.write(ctl + '\n')
            ack = 'MSH|^~\\&|RX|HOSP|TX|HOSP|20261105000000||ACK|A' + ctl + '|P|2.5.1\rMSA|AA|' + ctl + '|\r'
            p[0].sendall(b'\x0b' + ack.encode('latin-1') + b'\x1c\r')
