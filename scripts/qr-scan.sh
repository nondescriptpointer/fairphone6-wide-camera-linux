#!/bin/sh
# Capture a frame from the OV13B10 (ultra-wide) RDI path, save a viewable JPEG,
# and decode any QR code in it.
#   Output (in the current directory):
#            ./qr.jpg   (contrast-stretched grayscale, viewable + decoded)
#            ./qr.pgm   (raw grayscale levels)
OUTDIR=$(pwd)
M=/dev/media0
SD=$(media-ctl -d $M -e "ov13b10 1-0036")
V=$(media-ctl -d $M -e "msm_vfe0_video0")

# real image (test_pattern=0); manual exposure/gain (no 3A). Override via env:
#   EXPOSURE=.. GAIN=.. TESTPAT=.. ~/cam-bringup/qr-scan.sh
v4l2-ctl -d "$SD" --set-ctrl test_pattern=${TESTPAT:-0}      2>/dev/null
v4l2-ctl -d "$SD" --set-ctrl exposure=${EXPOSURE:-3000}      2>/dev/null
v4l2-ctl -d "$SD" --set-ctrl analogue_gain=${GAIN:-1000}     2>/dev/null

media-ctl -d $M -l "'msm_csiphy1':1 -> 'msm_csid0':0 [1]" 2>/dev/null
media-ctl -d $M -l "'msm_csid0':1 -> 'msm_vfe0_rdi0':0 [1]" 2>/dev/null
# NOTE: the sensor source pad must be set too - libcamera/PipeWire may have left
# it in a smaller mode, which fails media pipeline link validation (EPIPE).
for p in "'ov13b10 1-0036':0" "'msm_csiphy1':0" "'msm_csiphy1':1" "'msm_csid0':0" "'msm_csid0':1" "'msm_vfe0_rdi0':0"; do
	media-ctl -d $M -V "$p [fmt:SGRBG10_1X10/4208x3120]" 2>/dev/null
done
v4l2-ctl -d $V --set-fmt-video=width=4208,height=3120,pixelformat=pgAA >/dev/null 2>&1

# grab a few frames so exposure/gain settle, keep the last one
sudo v4l2-ctl -d $V --stream-mmap --stream-count=5 --stream-to=/tmp/frame.raw >/dev/null 2>&1
if [ ! -s /tmp/frame.raw ]; then
	echo "Capture produced no data. Is the libcamera/Snapshot camera still open?"
	echo "(close it, or note the raw V4L2 path and libcamera can't run at the same time)"
	exit 1
fi

OUTDIR="$OUTDIR" python3 - <<'PY'
from PIL import Image, ImageOps
W, H = 4208, 3120
fsz = 16423680
stride = fsz // H                      # 5264
d = open('/tmp/frame.raw', 'rb').read()
f = d[-fsz:] if len(d) >= fsz else d    # last (settled) frame

# Unpack MIPI RAW10 (4 px / 5 bytes) -> 8-bit MSB, half-res (skip every 2nd px/row)
ow, oh = W // 2, H // 2
out = bytearray(ow * oh)
for oy in range(oh):
    row = f[oy * 2 * stride: oy * 2 * stride + stride]
    # drop every 5th byte (the packed LSBs) -> 4208 MSB bytes, then take evens
    msb = bytes(b for i, b in enumerate(row[:5260]) if i % 5 != 4)
    o = oy * ow
    out[o:o + ow] = msb[::2]

import os
outdir = os.environ.get('OUTDIR', '.')
img = Image.frombytes('L', (ow, oh), bytes(out))
img.save(os.path.join(outdir, 'qr.pgm'))               # raw grayscale levels
view = ImageOps.autocontrast(img, cutoff=1)            # stretch for viewing
view.save(os.path.join(outdir, 'qr.jpg'), quality=90)  # viewable
print("gray mean=%d min=%d max=%d  ->  %s/qr.jpg (%dx%d)" %
      (sum(out)//len(out), min(out), max(out), outdir, ow, oh))

# Decode via libzbar directly (pyzbar) - no ImageMagick needed
print("--- decoding QR ---")
try:
    from pyzbar.pyzbar import decode
    found = decode(view) or decode(img)
    if found:
        for s in found:
            print("[%s] %s" % (s.type, s.data.decode('utf-8', 'replace')))
    else:
        print("[no QR found] open %s/qr.jpg to check framing/exposure" % outdir)
except Exception as e:
    print("decode error:", e)
PY
