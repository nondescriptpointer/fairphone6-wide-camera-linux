#!/bin/sh
# Set the OV13B10 ultra-wide focus (VCM DW9714/AW86017) live.
# Usage: ~/cam-bringup/set-focus.sh <0..1023>
#   0    = infinity (far)      ~400-550 = close (QR / documents)
# Works while the camera app is streaming (the lens is a separate v4l2 subdev).
V=${1:-400}
LENS=""
for s in /sys/class/video4linux/v4l-subdev*; do
	case "$(cat "$s/name" 2>/dev/null)" in
	*dw9714*|*9714*) LENS=/dev/$(basename "$s");;
	esac
done
[ -z "$LENS" ] && { echo "no dw9714 lens subdev found (is dw9714 loaded?)"; exit 1; }
v4l2-ctl -d "$LENS" --set-ctrl focus_absolute="$V" && echo "$LENS focus_absolute=$V"
