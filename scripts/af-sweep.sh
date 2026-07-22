#!/bin/sh
# Focus sweep for the OV13B10 ultra-wide VCM (DW9714/AW86017 @ i2c-1 0x0c).
# Point the camera at a DETAILED, well-lit subject ~10-40 cm away (text/QR),
# then run this. It steps focus_absolute across its range, captures a frame at
# each step and reports the sharpness so you can see AF works (sharpest = in focus).
#
# Run AFTER booting boot-NEW-camera.img (dw9714 + lens-focus DT).
M=/dev/media0

# locate the VCM lens subdev (dw9714) by name
LENS=""
for s in /sys/class/video4linux/v4l-subdev*; do
	case "$(cat "$s/name" 2>/dev/null)" in
	*dw9714*|*9714*) LENS=/dev/$(basename "$s");;
	esac
done
if [ -z "$LENS" ]; then
	echo "No dw9714 lens subdev found. Is the new DTB booted and dw9714 loaded?"
	echo "  ($ lsmod | grep dw9714 ; media-ctl -p -d $M | grep -i 9714)"
	exit 1
fi
echo "VCM lens subdev: $LENS"
v4l2-ctl -d "$LENS" --list-ctrls 2>/dev/null | grep -i focus

SD=$(media-ctl -d $M -e "ov13b10 1-0036")
V=$(media-ctl -d $M -e "msm_vfe0_video0")
v4l2-ctl -d "$SD" --set-ctrl test_pattern=0,exposure=2500,analogue_gain=800 2>/dev/null
media-ctl -d $M -l "'msm_csiphy1':1 -> 'msm_csid0':0 [1]" 2>/dev/null
media-ctl -d $M -l "'msm_csid0':1 -> 'msm_vfe0_rdi0':0 [1]" 2>/dev/null
for p in "'ov13b10 1-0036':0" "'msm_csiphy1':0" "'msm_csiphy1':1" "'msm_csid0':0" "'msm_csid0':1" "'msm_vfe0_rdi0':0"; do
	media-ctl -d $M -V "$p [fmt:SGRBG10_1X10/4208x3120]" 2>/dev/null
done
v4l2-ctl -d $V --set-fmt-video=width=4208,height=3120,pixelformat=pgAA >/dev/null 2>&1

best_f=0; best_s=0
for f in 0 128 256 384 512 640 768 896 1023; do
	v4l2-ctl -d "$LENS" --set-ctrl focus_absolute=$f 2>/dev/null
	sleep 0.4
	sudo v4l2-ctl -d $V --stream-mmap --stream-count=4 --stream-to=/tmp/af.raw >/dev/null 2>&1
	s=$(python3 - $f <<'PY'
import sys
d=open('/tmp/af.raw','rb').read(); H=3120; fsz=16423680; st=fsz//H; f=d[-fsz:]
tot=0;n=0
for y in range(1200,1900,3):
    row=f[y*st:y*st+5260]
    msb=bytes(b for i,b in enumerate(row) if i%5!=4)
    for x in range(800,3400,2): tot+=abs(msb[x]-msb[x-2]); n+=1
print("%.2f"%(tot/n))
PY
)
	echo "focus_absolute=$f   sharpness=$s"
	awk "BEGIN{exit !($s>$best_s)}" && best_s=$s && best_f=$f
done
echo "--> sharpest at focus_absolute=$best_f (sharpness $best_s)"
echo "If sharpness varies with focus, the VCM is moving = autofocus hardware works."
