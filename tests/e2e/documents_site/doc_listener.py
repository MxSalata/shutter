# usage: doc_listener.py PORT LOG [SECONDS]: an MLLP receiver that logs each control id, once per frame, and answers by its
# prefix: AE- an application error with words and an ERR segment, AR- a rejection, anything else AA.
import socket, sys, time
port, path = int(sys.argv[1]), sys.argv[2]
end = time.time() + float(sys.argv[3] if len(sys.argv) > 3 else 1800)
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', port))
s.listen(5)
s.settimeout(0.2)
log = open(path, 'a', buffering=1)
conns = []
while time.time() < end:
    try:
        c, _ = s.accept()
        c.settimeout(0.05)
        conns.append([c, b''])
    except socket.timeout:
        pass
    for p in list(conns):
        try:
            d = p[0].recv(1 << 20)
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
            code = ctl.split('-')[0] if ctl.split('-')[0] in ('AE', 'AR') else 'AA'
            words = {'AE': 'CANARYDIAG unknown patient', 'AR': 'CANARYDIAG validation error'}.get(code, '')
            text = 'MSH|^~\\&|RX|HOSP|TX|HOSP|20261105000000||ACK|A' + ctl + '|P|2.5.1\rMSA|' + code + '|' + ctl + '|' + words + '\r'
            if words:
                text += 'ERR||PID^1^3|204^Unknown key identifier^HL70357|E\r'
            p[0].sendall(b'\x0b' + text.encode('latin-1') + b'\x1c\r')
