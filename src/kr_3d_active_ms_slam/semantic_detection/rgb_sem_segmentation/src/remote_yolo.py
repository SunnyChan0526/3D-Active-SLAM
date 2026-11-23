"""Drop-in client for docker/yolo_gpu/yolo_server.py.

Mimics the parts of the ultralytics 8.0.38 API that detect.py uses:
    model.names[cls]
    res = model.predict(img, show=False)
    len(res[0]); res[0].masks.shape[0]; res[0].masks.masks[i].cpu().numpy()
    res[0].boxes.cls[i]; res[0].boxes.conf[i]
so detect.py's post-processing is unchanged.
"""
import json
import socket
import struct

import numpy as np
import torch


def _recv_exact(sock, n):
    buf = bytearray(n)
    view = memoryview(buf)
    got = 0
    while got < n:
        k = sock.recv_into(view[got:], n - got)
        if k == 0:
            raise ConnectionError("YOLO server closed the connection")
        got += k
    return bytes(buf)


class _Masks:
    def __init__(self, masks):
        self.masks = torch.from_numpy(masks.astype(np.float32))
        self.shape = self.masks.shape


class _Boxes:
    def __init__(self, cls, conf):
        self.cls = np.asarray(cls, dtype=np.float32)
        self.conf = np.asarray(conf, dtype=np.float32)


class _Result:
    def __init__(self, masks, cls, conf):
        self.masks = _Masks(masks) if len(cls) else None
        self.boxes = _Boxes(cls, conf)
        self._n = len(cls)

    def __len__(self):
        return self._n


class RemoteYOLO:
    def __init__(self, address, timeout=10.0):
        host, port = address.rsplit(":", 1)
        self.address = (host, int(port))
        self.timeout = timeout
        self.sock = None
        self.last_ms = None
        self._connect()
        meta, _ = self._call(0, 0, b"")
        self.names = {int(k): v for k, v in meta["names"].items()}

    def _connect(self):
        self.sock = socket.create_connection(self.address, timeout=self.timeout)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

    def _call(self, h, w, payload):
        for attempt in range(2):  # one reconnect if the server restarted
            try:
                if self.sock is None:
                    self._connect()
                self.sock.sendall(struct.pack("<4sII", b"YOLO", h, w) + payload)
                (jlen,) = struct.unpack("<I", _recv_exact(self.sock, 4))
                meta = json.loads(_recv_exact(self.sock, jlen))
                n = meta.get("n", 0)
                raw = _recv_exact(self.sock, n * meta["mh"] * meta["mw"]) if n else b""
                return meta, raw
            except (OSError, ConnectionError):
                if self.sock is not None:
                    self.sock.close()
                self.sock = None
                if attempt:
                    raise

    def predict(self, img, show=False, **_):
        img = np.ascontiguousarray(img, dtype=np.uint8)
        h, w = img.shape[:2]
        meta, raw = self._call(h, w, img.tobytes())
        self.last_ms = meta.get("ms")
        n = meta["n"]
        masks = (np.frombuffer(raw, np.uint8).reshape(n, meta["mh"], meta["mw"])
                 if n else np.zeros((0, h, w), np.uint8))
        return [_Result(masks, meta["cls"], meta["conf"])]
