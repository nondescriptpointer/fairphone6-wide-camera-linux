#!/bin/sh
# Post-boot camera bring-up check for milos CAMSS + OV13B10
echo "== running kernel =="; uname -r
echo "== booted slot =="; sudo qbootctl -c
echo
echo "== CAMSS / sensor probe (dmesg) =="
sudo dmesg | grep -iE 'camss|csid|csiphy|vfe|ov13b10|milos-camss|cci' | tail -40
echo
echo "== media / video nodes =="
ls -l /dev/media* /dev/video* /dev/v4l-subdev* 2>/dev/null
echo
echo "== modules loaded =="
lsmod | grep -iE 'camss|ov13b10|videobuf|v4l2'
echo
echo "== media topology (if present) =="
for m in /dev/media*; do [ -e "$m" ] && media-ctl -d "$m" -p 2>/dev/null; done
echo
echo "If /dev/media0 shows the milos camss graph and ov13b10 subdev: SUCCESS."
echo "To make this slot (_a) permanent once verified:  sudo qbootctl -m"
