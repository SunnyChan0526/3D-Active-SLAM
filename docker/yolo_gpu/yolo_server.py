#!/usr/bin/env python3
"""GPU YOLOv8-seg inference server for Jetson.

The main ActiveSLAM container is Ubuntu 20.04 (ROS Noetic), which cannot use
JetPack 6's CUDA 12.6. This server runs in a JetPack 6 container instead and
rgb_sem_segmentation/src/remote_yolo.py talks to it over localhost TCP.

Protocol (all integers little-endian uint32):
  request : b"YOLO" | h | w | h*w*3 bytes BGR uint8      (h = w = 0: hello)
  response: json_len | json | n*mh*mw bytes uint8 masks
            json = {"names": {...}}                       for hello
            json = {"n", "mh", "mw", "cls", "conf", "ms"} for a frame
"""
import argparse
import json
import socketserver
import struct
import threading
import time

import numpy as np
import torch
from ultralytics import YOLO

MAGIC = b"YOLO"


def recv_exact(sock, n):
    buf = bytearray(n)
    view = memoryview(buf)
    got = 0
    while got < n:
        k = sock.recv_into(view[got:], n - got)
        if k == 0:
            raise ConnectionError("client closed")
        got += k
    return bytes(buf)


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        srv = self.server
        sock = self.request
        sock.setsockopt(socketserver.socket.IPPROTO_TCP, socketserver.socket.TCP_NODELAY, 1)
        try:
            while True:
                magic, h, w = struct.unpack("<4sII", recv_exact(sock, 12))
                if magic != MAGIC:
                    return
                if h == 0 or w == 0:
                    self.reply({"names": {int(k): v for k, v in srv.model.names.items()}})
                    continue
                img = np.frombuffer(recv_exact(sock, h * w * 3), np.uint8).reshape(h, w, 3)
                t = time.time()
                with srv.lock:
                    res = srv.model.predict(img, show=False, verbose=False,
                                            device=srv.device, half=srv.half)[0]
                if len(res) and res.masks is not None:
                    masks = (res.masks.masks > 0.5).to(torch.uint8).cpu().numpy()
                    cls = res.boxes.cls.cpu().numpy().astype(int).tolist()
                    conf = res.boxes.conf.cpu().numpy().astype(float).tolist()
                else:
                    masks = np.zeros((0, h, w), np.uint8)
                    cls, conf = [], []
                ms = (time.time() - t) * 1000.0
                self.reply({"n": len(cls), "mh": int(masks.shape[1]), "mw": int(masks.shape[2]),
                            "cls": cls, "conf": conf, "ms": ms}, masks.tobytes())
        except (ConnectionError, BrokenPipeError, ConnectionResetError):
            return

    def reply(self, meta, payload=b""):
        js = json.dumps(meta).encode()
        self.request.sendall(struct.pack("<I", len(js)) + js + payload)


class Server(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="/models/yolov8x-seg.pt")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--fp32", action="store_true", help="disable FP16")
    args = ap.parse_args()

    cuda = torch.cuda.is_available()
    print(f"torch {torch.__version__}, CUDA available: {cuda}", flush=True)
    srv = Server((args.host, args.port), Handler)
    srv.model = YOLO(args.model)
    srv.device = 0 if cuda else "cpu"
    srv.half = cuda and not args.fp32
    srv.lock = threading.Lock()

    # Warm-up (CUDA kernels / cuDNN autotune) so the first real frame is fast.
    dummy = np.zeros((480, 640, 3), np.uint8)
    for _ in range(3):
        srv.model.predict(dummy, show=False, verbose=False, device=srv.device, half=srv.half)
    t = time.time()
    for _ in range(5):
        srv.model.predict(dummy, show=False, verbose=False, device=srv.device, half=srv.half)
    print(f"Warm-up done: {(time.time() - t) / 5 * 1000:.0f} ms/frame "
          f"(device={srv.device}, half={srv.half})", flush=True)
    print(f"Listening on {args.host}:{args.port}", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
