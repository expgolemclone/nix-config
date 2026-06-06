"""Resolve domains via external DNS (1.1.1.1) and update /etc/hosts."""

import os
import socket
import struct
import sys
import tempfile

MARKER_BEGIN: str = "# BEGIN piano-cxense"
MARKER_END: str = "# END piano-cxense"
HOSTS_PATH: str = "/etc/hosts"
DNS_SERVER: str = "1.1.1.1"
DNS_TIMEOUT: int = 3

DOMAINS: list[str] = [
    "code.piano.io",
    "c2-ap.piano.io",
    "buy-ap.piano.io",
    "api-esp-ap.piano.io",
    "cdn.cxense.com",
    "comcluster.cxense.com",
    "api.cxense.com",
    "accounts.youtube.com",
    "play.google.com",
]


def dns_query(domain: str) -> list[str]:
    tid: bytes = os.urandom(2)
    qname: bytes = b""
    for part in domain.split("."):
        qname += bytes([len(part)]) + part.encode()
    qname += b"\x00"
    packet: bytes = (
        tid + b"\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00" + qname + b"\x00\x01\x00\x01"
    )
    s: socket.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(DNS_TIMEOUT)
    s.sendto(packet, (DNS_SERVER, 53))
    resp: bytes = s.recv(512)
    s.close()

    pos: int = 12
    while resp[pos] != 0:
        pos += resp[pos] + 1
    pos += 5

    ips: list[str] = []
    ancount: int = struct.unpack("!H", resp[6:8])[0]
    for _ in range(ancount):
        if resp[pos] & 0xC0 == 0xC0:
            pos += 2
        else:
            while resp[pos] != 0:
                pos += resp[pos] + 1
            pos += 1
        rtype: int = struct.unpack("!H", resp[pos : pos + 2])[0]
        rdlen: int = struct.unpack("!H", resp[pos + 8 : pos + 10])[0]
        pos += 10
        if rtype == 1 and rdlen == 4:
            ips.append(".".join(str(b) for b in resp[pos : pos + 4]))
        pos += rdlen
    return ips


def resolve_all() -> list[str]:
    entries: list[str] = []
    for domain in DOMAINS:
        try:
            ips: list[str] = dns_query(domain)
            if ips:
                entries.append(f"{ips[0]} {domain}")
        except (OSError, struct.error) as exc:
            print(f"DNS resolution failed for {domain}: {exc}")
    return entries


def update_hosts(entries: list[str]) -> None:
    with open(HOSTS_PATH, "r") as f:
        content: str = f.read()

    new_block: str = MARKER_BEGIN + "\n" + "\n".join(entries) + "\n" + MARKER_END

    if MARKER_BEGIN in content:
        lines: list[str] = content.splitlines(keepends=True)
        result: list[str] = []
        inside: bool = False
        for line in lines:
            if line.rstrip() == MARKER_BEGIN:
                result.append(new_block + "\n")
                inside = True
            elif line.rstrip() == MARKER_END:
                inside = False
            elif not inside:
                result.append(line)
        content = "".join(result)
    else:
        content = content.rstrip("\n") + "\n" + new_block + "\n"

    fd, tmp_path = tempfile.mkstemp(dir="/etc")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
        os.chmod(tmp_path, 0o644)
        os.rename(tmp_path, HOSTS_PATH)
    except OSError:
        os.unlink(tmp_path)
        raise


def main() -> None:
    entries: list[str] = resolve_all()
    if not entries:
        print("DNS resolution failed for all domains, skipping update")
        sys.exit(0)

    print(f"Resolved {len(entries)}/{len(DOMAINS)} domains:")
    for entry in entries:
        print(f"  {entry}")

    update_hosts(entries)
    print("Updated /etc/hosts")


if __name__ == "__main__":
    main()
