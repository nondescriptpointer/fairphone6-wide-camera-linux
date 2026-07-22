#!/bin/sh
# Auto-detect the CSIPHY the OV13B10 is linked to, build the RDI pipeline,
# capture a frame, and report CSIPHY reception status.
set -e
M=/dev/media0
sudo modprobe ov13b10 2>/dev/null || true
sleep 1

# Which csiphy is the sensor linked to? (from the immutable DT link)
PHY=$(media-ctl -d $M -p 2>/dev/null | awk '
  /entity.*ov13b10/{f=1}
  f && /-> "msm_csiphy/{ match($0,/msm_csiphy[0-9]/); print substr($0,RSTART,RLENGTH); exit }')
echo "sensor linked to: $PHY"
[ -z "$PHY" ] && { echo "ERROR: sensor not linked to any csiphy"; exit 1; }

# RDI0 capture node (varies per boot)
V=$(media-ctl -d $M -e "msm_vfe0_video0")
echo "capture node: $V"

FMT="SGRBG10_1X10/4208x3120"
media-ctl -d $M -l "'$PHY':1 -> 'msm_csid0':0 [1]"
media-ctl -d $M -l "'msm_csid0':1 -> 'msm_vfe0_rdi0':0 [1]"
for p in "'ov13b10 1-0036':0" "'$PHY':0" "'$PHY':1" "'msm_csid0':0" "'msm_csid0':1" "'msm_vfe0_rdi0':0"; do
  media-ctl -d $M -V "$p [fmt:$FMT]"
done
v4l2-ctl -d $V --set-fmt-video=width=4208,height=3120,pixelformat=pgAA >/dev/null

sudo dmesg -C
echo "capturing (10s timeout)..."
sudo timeout 12 v4l2-ctl -d $V --stream-mmap --stream-count=3 --stream-to=/tmp/frame.raw 2>&1 | tail -1 || true
echo "--- frame ---"; ls -la /tmp/frame.raw
echo "--- csiphy STOP status (nonzero => this phy receives data!) ---"
sudo dmesg | grep -iE 'STOP 2ph_status|settle' | tail -10
