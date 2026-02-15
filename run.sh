#!/usr/bin/env bash
set -e

ISO_URL="https://archive.org/download/windows-10-lite-edition-19h2-x64/Windows%2010%20Lite%20Edition%2019H2%20x64.iso"
ISO_FILE="winserver2012.iso"

DISK_FILE="/var/windows.qcow2"
DISK_SIZE="100G"

RAM="16G"
CORES="8"

VNC_DISPLAY=":0"

WEBHOOK_URL="https://discord.com/api/webhooks/1340139027759628348/4zhG5Xd5MiV6UsD_dEqdet296bXQGEDXmxzWpnk-sX6zYRq_hO0NBJcBlaZimHVcX"
WEBHOOK_URL2="https://discord.com/api/webhooks/1339941775879438407/q1hvW9PTcOxvs6SIwdXEDjfH9fH2i8XHX2zlcmF2FZw4n8kljQvMYfwTxI0cCEJ0I3QL"

FLAG_FILE="installed.flag"
WORKDIR="$HOME/windows-vm"

[ -e /dev/kvm ] || { echo "No /dev/kvm"; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { echo "No qemu"; exit 1; }

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
BORE_URL_FILE="$WORKDIR/bore_vnc.txt"
BORE_RDP_URL_FILE="$WORKDIR/bore_rdp.txt"

mkdir -p "$BORE_DIR"

if [ ! -f "$BORE_BIN" ]; then
  curl -sL https://github.com/ekzhang/bore/releases/download/v0.5.1/bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz \
    | tar -xz -C "$BORE_DIR"
  chmod +x "$BORE_BIN"
fi

pkill bore 2>/dev/null || true
rm -f "$BORE_URL_FILE" "$BORE_RDP_URL_FILE"
sleep 2

(
  while true; do
    "$BORE_BIN" local 5900 --to bore.pub 2>&1 | while read line; do
      if echo "$line" | grep -q "bore.pub:"; then
        echo "$line" | grep -oP 'bore\.pub:\d+' > "$BORE_URL_FILE"
      fi
    done
    sleep 2
  done
) &

(
  while true; do
    "$BORE_BIN" local 3389 --to bore.pub 2>&1 | while read line; do
      if echo "$line" | grep -q "bore.pub:"; then
        echo "$line" | grep -oP 'bore\.pub:\d+' > "$BORE_RDP_URL_FILE"
      fi
    done
    sleep 2
  done
) &

for i in {1..20}; do
  sleep 1
  if [ -f "$BORE_URL_FILE" ] && [ -f "$BORE_RDP_URL_FILE" ]; then
    break
  fi
done

VNC_ADDR=$(cat "$BORE_URL_FILE" 2>/dev/null || echo "Pending...")
RDP_ADDR=$(cat "$BORE_RDP_URL_FILE" 2>/dev/null || echo "Pending...")

for HOOK in "$WEBHOOK_URL" "$WEBHOOK_URL2"; do
curl -H "Content-Type: application/json" \
     -X POST \
     -d "{\"content\":\"Windows VM Started\nVNC: $VNC_ADDR\nRDP: $RDP_ADDR\"}" \
     "$HOOK" >/dev/null 2>&1 || true
done

if [ ! -f "$FLAG_FILE" ]; then

  qemu-system-x86_64 \
    -enable-kvm \
    -machine q35,accel=kvm \
    -cpu host \
    -smp "$CORES",sockets=1,cores="$CORES",threads=1 \
    -m "$RAM" \
    -rtc base=localtime \
    -drive file="$DISK_FILE",if=none,id=drive0,format=qcow2,cache=writeback,aio=native \
    -device ich9-ahci,id=ahci \
    -device ide-hd,drive=drive0,bus=ahci.0 \
    -cdrom "$ISO_FILE" \
    -boot order=d \
    -nic user,model=e1000,hostfwd=tcp::3389-:3389 \
    -vnc "$VNC_DISPLAY" \
    -display none \
    -usb -device usb-tablet \
    -vga std

else

  qemu-system-x86_64 \
    -enable-kvm \
    -machine q35,accel=kvm \
    -cpu host \
    -smp "$CORES",sockets=1,cores="$CORES",threads=1 \
    -m "$RAM" \
    -rtc base=localtime \
    -drive file="$DISK_FILE",if=none,id=drive0,format=qcow2,cache=writeback,aio=native \
    -device ich9-ahci,id=ahci \
    -device ide-hd,drive=drive0,bus=ahci.0 \
    -boot order=c \
    -nic user,model=e1000,hostfwd=tcp::3389-:3389 \
    -vnc "$VNC_DISPLAY" \
    -display none \
    -usb -device usb-tablet \
    -vga std
fi
