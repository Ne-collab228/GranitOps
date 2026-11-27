"""List or extract selected members of a remote zip over HTTP range requests.

usage: remote_zip.py URL list
       remote_zip.py URL extract OUT_DIR name1 name2 ...
"""
import io
import os
import sys
import urllib.request
import zipfile

UA = "generic-client"
BLOCK = 4 * 1024 * 1024


def resolve(url):
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.geturl(), int(r.headers["Content-Length"])


class HttpFile(io.RawIOBase):
    def __init__(self, url):
        self.url, self.size = resolve(url)
        self.pos = 0
        self.cache = {}
        self.fetched = 0

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        if whence == 0:
            self.pos = off
        elif whence == 1:
            self.pos += off
        else:
            self.pos = self.size + off
        return self.pos

    def _block(self, idx):
        if idx not in self.cache:
            start = idx * BLOCK
            end = min(start + BLOCK, self.size) - 1
            for attempt in range(5):
                try:
                    req = urllib.request.Request(
                        self.url,
                        headers={"User-Agent": UA, "Range": "bytes=%d-%d" % (start, end)},
                    )
                    with urllib.request.urlopen(req, timeout=120) as r:
                        data = r.read()
                    break
                except Exception as e:  # retry, re-resolving the signed URL
                    if attempt == 4:
                        raise
                    self.url, _ = resolve(SRC)
            self.fetched += len(data)
            if len(self.cache) > 6:
                self.cache.pop(next(iter(self.cache)))
            self.cache[idx] = data
        return self.cache[idx]

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.size - self.pos
        n = min(n, self.size - self.pos)
        out = bytearray()
        while n > 0:
            idx = self.pos // BLOCK
            off = self.pos % BLOCK
            chunk = self._block(idx)[off:off + n]
            if not chunk:
                break
            out += chunk
            self.pos += len(chunk)
            n -= len(chunk)
        return bytes(out)

    def readinto(self, b):
        data = self.read(len(b))
        b[:len(data)] = data
        return len(data)


SRC = sys.argv[1]
mode = sys.argv[2]
f = HttpFile(SRC)
z = zipfile.ZipFile(io.BufferedReader(f, buffer_size=1024 * 1024))
if mode == "list":
    for i in z.infolist():
        print("%10.1f MB  %s" % (i.file_size / 1048576, i.filename))
else:
    out_dir = sys.argv[3]
    os.makedirs(out_dir, exist_ok=True)
    wanted = sys.argv[4:]
    for i in z.infolist():
        base = os.path.basename(i.filename)
        if base in wanted:
            dst = os.path.join(out_dir, base)
            with z.open(i) as src, open(dst, "wb") as dstf:
                while True:
                    buf = src.read(1024 * 1024)
                    if not buf:
                        break
                    dstf.write(buf)
            print("extracted", base, os.path.getsize(dst))
print("bytes fetched: %.1f MB" % (f.fetched / 1048576))
