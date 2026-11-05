# usage: ack_listener.py PORT LOG [SECONDS]: an MLLP receiver that answers by the message's control id, up to its first dash.
# AA-, CA-, AE-, CE-, AR-, CR-: that code. NM-: a reply with no MSA. NR-: no reply at all. CL-: closes with no reply.
# C2-: CA, then AE, on one connection. Anything else: CA, as a listener that takes a message before its application has seen it.
import socket, sys, time
port, path = int(sys.argv[1]), sys.argv[2]
end = time.time() + float(sys.argv[3] if len(sys.argv) > 3 else 1200)
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', port))
s.listen(5)
s.settimeout(0.2)
log = open(path, 'a', buffering=1)
conns = []


def ack(ctl, code):
    text = 'MSH|^~\\&|RX|HOSP|TX|HOSP|20261105000000||ACK|A' + ctl + '|P|2.5.1\r'
    if code:
        text += 'MSA|' + code + '|' + ctl + '|\r'
    return b'\x0b' + text.encode('latin-1') + b'\x1c\r'


while time.time() < end:
    try:
        c, _ = s.accept()
        c.settimeout(0.05)
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
            kind = ctl.split('-')[0]
            if kind == 'NR':
                continue
            if kind == 'CL':
                p[0].close()
                conns.remove(p)
                break
            if kind == 'C2':
                p[0].sendall(ack(ctl, 'CA') + ack(ctl, 'AE'))
            elif kind == 'NM':
                p[0].sendall(ack(ctl, ''))
            else:
                p[0].sendall(ack(ctl, kind if kind in ('AA', 'CA', 'AE', 'CE', 'AR', 'CR') else 'CA'))
