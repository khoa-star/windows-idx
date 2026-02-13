#!/usr/bin/env bash
set -e

### CONFIG ###
ISO_URL="https://go.microsoft.com/fwlink/p/?LinkID=2195443"
ISO_FILE="winserver2012.iso"

DISK_FILE="/var/windows.qcow2"
DISK_SIZE="100G"

RAM="16G"
CORES="8"

VNC_DISPLAY=":0"

WEBHOOK_URL="https://discord.com/api/webhooks/1340139027759628348/4zhG5Xd5MiV6UsD_dEqdet296bXQGEDXmxzWpnk-sX6zYRQYRq_hO0NBJcBlaZimHVcX"

FLAG_FILE="installed.flag"
WORKDIR="$HOME/windows-vm"

### CHECK ###
[ -e /dev/kvm ] || { echo "❌ No /dev/kvm"; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { echo "❌ No qemu"; exit 1; }

### PREP ###
mkdir -p "$WORKDIR"
cd "$WORKDIR"
chmod 755 "$WORKDIR"

[ -f "$DISK_FILE" ] || qemu-img create -f qcow2 "$DISK_FILE" "$DISK_SIZE"

if [ ! -f "$FLAG_FILE" ]; then
  if [ ! -f "$ISO_FILE" ]; then
    echo "📥 Download Windows Server 2012 R2..."
    wget --continue --no-check-certificate --show-progress -O "$ISO_FILE" "$ISO_URL"
    echo "✅ Download done"
  fi
fi

#########################
# BORE AUTO-RESTART    #
#########################
BORE_DIR="$HOME/.bore"
BORE_BIN="$BORE_DIR/bore"
BORE_URL_FILE="$WORKDIR/bore_url.txt"

mkdir -p "$BORE_DIR"

if [ ! -f "$BORE_BIN" ]; then
  curl -sL https://github.com/ekzhang/bore/releases/download/v0.5.1/bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz \
    | tar -xz -C "$BORE_DIR"
  chmod +x "$BORE_BIN"
fi

pkill bore 2>/dev/null || true
rm -f "$BORE_URL_FILE"
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
BORE_KEEPER_PID=$!

echo -n "⏳ Waiting Bore"
for i in {1..15}; do
  sleep 1
  echo -n "."
  if [ -f "$BORE_URL_FILE" ]; then
    break
  fi
done
echo ""

if [ -f "$BORE_URL_FILE" ]; then
  BORE_ADDR=$(cat "$BORE_URL_FILE")
else
  BORE_ADDR="Pending..."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌍 VNC: $BORE_ADDR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"

############################
# SEND TO DISCORD WEBHOOK #
############################
curl -H "Content-Type: application/json" \
     -X POST \
     -d "{\"content\":\"🖥️ Windows Server 2012 R2 Started\nVNC: $BORE_ADDR\"}" \
     "$WEBHOOK_URL" >/dev/null 2>&1 || true

#################
# RUN QEMU     #
#################
if [ ! -f "$FLAG_FILE" ]; then

  echo ""
  echo "⚠️ INSTALL MODE - WINDOWS SERVER 2012 R2"
  echo "Inside VNC:"
  echo "1. Install now"
  echo "2. Custom install"
  echo "3. Select disk → Next"
  echo "4. Set Administrator password"
  echo ""
  echo "After finished, type: xong"
  echo ""

  qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -smp "$CORES" \
    -m "$RAM" \
    -machine q35 \
    -drive file="$DISK_FILE",if=ide,format=qcow2 \
    -cdrom "$ISO_FILE" \
    -boot order=d \
    -netdev user,id=net0 \
    -device e1000,netdev=net0 \
    -vnc "$VNC_DISPLAY" \
    -usb -device usb-tablet \
    -vga std &

  QEMU_PID=$!

  while true; do
    read -rp "Type 'xong': " DONE
    if [ "$DONE" = "xong" ]; then
      touch "$FLAG_FILE"
      kill "$QEMU_PID" 2>/dev/null || true
      kill "$BORE_KEEPER_PID" 2>/dev/null || true
      pkill bore 2>/dev/null || true
      rm -f "$ISO_FILE"
      echo "✅ Installation completed"
      exit 0
    fi
  done

else

  echo "✅ Boot Windows Server 2012 R2"

  qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -smp "$CORES" \
    -m "$RAM" \
    -machine q35 \
    -drive file="$DISK_FILE",if=ide,format=qcow2 \
    -boot order=c \
    -netdev user,id=net0 \
    -device e1000,netdev=net0 \
    -vnc "$VNC_DISPLAY" \
    -usb -device usb-tablet \
    -vga std
fi
