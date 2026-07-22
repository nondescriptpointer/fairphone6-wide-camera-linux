# fairphone6-wide-camera-linux

Experimental **mainline Linux** support for the **Fairphone 6** (Qualcomm _milos_ / SM7635)
**ultra-wide camera** (OmniVision OV13B10), on postmarketOS.

Working: full capture pipeline (OV13B10 → CSIPHY v2.2.1 → CSID665 → TFE665 → DDR), libcamera
software ISP, auto-exposure/AWB, gstreamer + PipeWire, the GNOME **Camera/Snapshot** app, fixed-focus
autofocus hardware, upright orientation.

> ⚠️ **Experimental.** Targets one device + one kernel revision (below). Only the ultra-wide
> works; no true autofocus; preview FOV is cropped. See **Limitations**. Read [this](https://nondescriptpointer.com/articles/fairphone-6-wide-camera-linux/) for the
> full story of how this was built.

## Target revisions (reproducibility)

| Component | Base                                                      |
| --------- | --------------------------------------------------------- |
| Kernel    | `milos-mainline/linux` tag **`v7.1.2-milos`**             |
| libcamera | **v0.7.2** (as packaged by postmarketOS `temp/libcamera`) |
| Distro    | postmarketOS (edge), Fairphone 6 (`fairphone-fp6`)        |

## Repository layout

```
kernel/     5 git-format-patch commits against v7.1.2-milos
libcamera/  2 patches against libcamera v0.7.2 (sensor helper + properties)
pmaports/   diffs for the kernel config and the libcamera APKBUILD
udev/       fixed-focus rule
scripts/    capture / focus / helper tools
```

## What each patch does

**kernel/** (apply in order onto `v7.1.2-milos`):

1. `TFE665 (VFE) support` — the ISP driver (vfe-665), a TFE530/vfe-340 adaptation. Contains the
   key fix: 128-bit RDI `rdi_width` → packer `0x0` (not `PLAIN64`), which is what made frames
   contain real pixels instead of zeros.
2. `CSIPHY v2.2.1 lane config` — D-PHY lane sequence + datarate/AFE tuning for milos.
3. `milos resources + compatible` — camss core: 4 CSIPHY / 3 CSID / 3 TFE, clocks (incl. the
   essential `soc_ahb`), interconnects, `qcom,milos-camss`.
4. `dts: CAMSS + FP6 ultra-wide camera` — `camss@ac13000`, the OV13B10 node (CSIPHY1, 4 lanes,
   19.2 MHz MCLK), the DW9714/AW86017 focus VCM + `lens-focus`, orientation/rotation.
5. `ov13b10: OF match, selection API, disable broken binned modes`.

**libcamera/** (add to the pmaports `temp/libcamera` APKBUILD _after_ its existing 0001/0002):

- `0003` — OV13B10 sensor helper (`gain = code/128`) → enables software auto-exposure/AWB.
- `0004` — OV13B10 sensor properties (unit cell, test-pattern map).

## Build & install

### Kernel (native on-device or cross)

```sh
git clone https://github.com/<you>/linux -b v7.1.2-milos && cd linux   # or the milos-mainline fork
git am /path/to/fp6-mainline-camera/kernel/*.patch
# enable in your config:  CONFIG_VIDEO_OV13B10=m  CONFIG_VIDEO_DW9714=m  (+ milos camcc/CCI/CAMSS)
make ARCH=arm64 LLVM=1 -j"$(nproc)"        # Image + modules + dtbs
```

Install the kernel image/dtb the way your device expects (on FP6/pmOS: rebuild the
`linux-postmarketos-qcom-milos` package, or replace the boot image), then
`make modules_install`.

### libcamera (via pmaports)

```sh
cd pmaports/temp/libcamera
cp /path/to/fp6-mainline-camera/libcamera/000{3,4}-*.patch .
# add both to source= and sha512sums in the APKBUILD (see pmaports/libcamera-APKBUILD.diff),
# bump pkgrel, then:
abuild -r
```

### Runtime bits

```sh
sudo cp udev/99-ov13b10-focus.rules /etc/udev/rules.d/ && sudo udevadm control --reload
# packages needed for apps + the QR helper:
sudo apk add libcamera-gstreamer gstreamer-tools pipewire-spa-libcamera py3-pyzbar py3-pillow
```

## Verify

```sh
dmesg | grep -iE 'camss|csid|csiphy|vfe|ov13b10|dw9714'   # bind, no errors
media-ctl -d /dev/media0 -p                                # graph incl. dw9714 lens
cam -l                                                     # libcamera sees 'ov13b10'
wpctl status | grep -i ov13b10                             # PipeWire 'ov13b10 [libcamera]'
./scripts/qr-scan.sh                                       # raw QR capture+decode
./scripts/set-focus.sh 300                                 # retune fixed focus (0..1023)
```

Then open GNOME **Camera**: upright, auto-exposed preview; close-up QR crisp.

## Limitations

- Only the **ultra-wide (OV13B10)** works; main (IMX896) and front (S5KKD1) have no mainline
  drivers.
- **No autofocus** — libcamera's software ISP has no AF loop; focus is a fixed position
  (udev default 300; retune with `scripts/set-focus.sh`).
- **Preview FOV is cropped** — the 2×2-binned sensor modes are broken on this path and disabled,
  so the software ISP crops (doesn't scale) a larger mode → a zoomed 1080p preview.
- Power sequencing is simplified (regulators forced on); software-only ISP.

## Upstreaming (help welcome)

- **libcamera** sensor helper/properties
- **ov13b10** OF/selection changes → linux-media.
- **milos CAMSS** support → linux-media
- **Packaging** (config, libcamera patches, udev rule) → postmarketOS pmaports MR.

## Licensing

The kernel patches are GPL-2.0 (they modify GPL-2.0 kernel files); the libcamera patches are
LGPL-2.1 (matching libcamera).
