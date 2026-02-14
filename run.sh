#!/usr/bin/env bash
set -e

### CONFIG ###
ISO_URL="https://archive.org/download/android-x-86-11-r-arm-x86-64-iso/Android-x86%2011-R%202022-05-04%20%28x86_64%29%20k5.4.140-M21-arm-noGapps-addViaBrowser-by-Xigo.iso"
ISO_FILE="android11.iso"

DISK_FILE="/var/android.qcow2"
DISK_SIZE="100G"

RAM="16G"
CORES="8"

VNC_DISPLAY=":0"

WEBHOOK_URL="https://discord.com/api/webhooks/1340139027759628348/4zhG5Xd5MiV6UsD_dEqdet296bXQGEDXmxzWpnk-sX6zYRQYRq_hO0NBJcBlaZimHVcX"
WEBHOOK_URL2="https://discord.com/api/webhooks/1339941775879438407/q1hvW9PTcOxvs6SIwdXEDjfH9fH2i8XHX2zlcmF2FZw4n8kljQvMYfwTxI0cCEJ0I3QL"

FLAG_FILE="installed.flag"
WORKDIR="$HOME/android-vm"

### CHECK ###
[ -e /dev/kvm ] || { echo "❌ No /dev/kvm"; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { echo "❌ No qemu"; exit 1; }

### PREP ###
mkdir -p "$WORKDIR"
cd "$WORKDIR"
chmod 755 "$WORKDIR"

[ -f "$DISK_FILE" ] || qemu-img create -f qcow2 "$DISK_FILE" "$DISK_SIZE"

if [ -f "$ISO_FILE" ]; then
  if [ ! -s "$ISO_FILE" ]; then
    rm -f "$ISO_FILE"
  fi
fi

if [ ! -f "$ISO_FILE" ]; then
  curl -L --fail --progress-bar -o "$ISO_FILE" "$ISO_URL"
fi

BORE_DIR="$HOME/.bore"
BORE_BIN="$BORE_DIR/bore"
BORE_VNC_FILE="$WORKDIR/bore_vnc.txt"
BORE_ADB_FILE="$WORKDIR/bore_adb.txt"

mkdir -p "$BORE_DIR"

if [ ! -f "$BORE_BIN" ]; then
  curl -sL https://github.com/ekzhang/bore/releases/download/v0.5.1/bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz \
    | tar -xz -C "$BORE_DIR"
  chmod +x "$BORE_BIN"
fi

pkill bore 2>/dev/null || true
rm -f "$BORE_VNC_FILE" "$BORE_ADB_FILE"
sleep 2

(
  while true; do
    "$BORE_BIN" local 5900 --to bore.pub 2>&1 | while read line; do
      if echo "$line" | grep -q "bore.pub:"; then
        echo "$line" | grep -oP 'bore\.pub:\d+' > "$BORE_VNC_FILE"
      fi
    done
    sleep 2
  done
) &

(
  while true; do
    "$BORE_BIN" local 5555 --to bore.pub 2>&1 | while read line; do
      if echo "$line" | grep -q "bore.pub:"; then
        echo "$line" | grep -oP 'bore\.pub:\d+' > "$BORE_ADB_FILE"
      fi
    done
    sleep 2
  done
) &

for i in {1..20}; do
  sleep 1
  if [ -f "$BORE_VNC_FILE" ] && [ -f "$BORE_ADB_FILE" ]; then
    break
  fi
done

VNC_ADDR=$(cat "$BORE_VNC_FILE" 2>/dev/null || echo "Pending...")
ADB_ADDR=$(cat "$BORE_ADB_FILE" 2>/dev/null || echo "Pending...")

for HOOK in "$WEBHOOK_URL" "$WEBHOOK_URL2"; do
curl -H "Content-Type: application/json" \
     -X POST \
     -d "{\"content\":\"📱 Android 11 VM Started\nVNC: $VNC_ADDR\nADB: $ADB_ADDR\"}" \
     "$HOOK" >/dev/null 2>&1 || true
done

#################
# RUN QEMU     #
#################

if [ ! -f "$FLAG_FILE" ]; then

  qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -smp "$CORES" \
    -m "$RAM" \
    -machine q35 \
    -drive file="$DISK_FILE",if=ide,format=qcow2 \
    -cdrom "$ISO_FILE" \
    -boot order=d \
    -nic user,model=e1000,hostfwd=tcp::5555-:5555 \
    -vnc "$VNC_DISPLAY" \
    -usb -device usb-tablet \
    -vga std

else

  qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -smp "$CORES" \
    -m "$RAM" \
    -machine q35 \
    -drive file="$DISK_FILE",if=ide,format=qcow2 \
    -boot order=c \
    -nic user,model=e1000,hostfwd=tcp::5555-:5555 \
    -vnc "$VNC_DISPLAY" \
    -usb -device usb-tablet \
    -vga std
fi
