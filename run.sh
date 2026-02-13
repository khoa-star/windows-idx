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
    echo "📥 Đang tải Windows Server 2012 R2..."
    wget --continue --no-check-certificate --show-progress -O "$ISO_FILE" "$ISO_URL"
    echo "✅ Tải xong!"
    ls -lh "$ISO_FILE"
  fi
fi

#########################
# BORE AUTO-RESTART    #
#########################
BORE_DIR="$HOME/.bore"
BORE_BIN="$BORE_DIR/bore"
BORE_LOG="$WORKDIR/bore.log"
BORE_URL_FILE="$WORKDIR/bore_url.txt"

mkdir -p "$BORE_DIR"

if [ ! -f "$BORE_BIN" ]; then
  curl -sL https://github.com/ekzhang/bore/releases/download/v0.5.1/bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz \
    | tar -xz -C "$BORE_DIR"
  chmod +x "$BORE_BIN"
fi

pkill bore 2>/dev/null || true
rm -f "$BORE_LOG" "$BORE_URL_FILE"
sleep 2

(
  while true; do
    "$BORE_BIN" local 5900 --to bore.pub 2>&1 | tee -a "$BORE_LOG" | while read line; do
      if echo "$line" | grep -q "bore.pub:"; then
        echo "$line" | grep -oP 'bore\.pub:\d+' > "$BORE_URL_FILE"
      fi
    done
    sleep 2
  done
) &
BORE_KEEPER_PID=$!

echo -n "⏳ Chờ Bore"
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
  BORE_ADDR="Chờ..."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌍 VNC: $BORE_ADDR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

############################
# SEND TO DISCORD WEBHOOK #
############################
curl -H "Content-Type: application/json" \
     -X POST \
     -d "{\"content\":\"🖥️ Windows Server 2012 R2 VM Started\nVNC: $BORE_ADDR\"}" \
     "$WEBHOOK_URL" >/dev/null 2>&1 || true

#################
# RUN QEMU     #
#################
if [ ! -f "$FLAG_FILE" ]; then

  echo ""
  echo "⚠️  CHẾ ĐỘ CÀI WINDOWS SERVER 2012 R2"
  echo ""
  echo "📋 TRONG VNC:"
  echo "   1. Chọn Language → Next"
  echo "   2. Click 'Install now'"
  echo "   3. Chọn bản Standard/Datacenter"
  echo "   4. Accept License"
  echo "   5. Chọn 'Custom: Install Windows only'"
  echo "   6. Chọn ổ đĩa → Next"
  echo "   7. Chờ cài đặt"
  echo "   8. Đặt mật khẩu Administrator"
  echo ""
  echo "👉 Sau khi cài xong và vào Desktop, gõ 'xong'"
  echo ""

  qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -smp "$CORES" \
    -m "$RAM" \
    -machine q35 \
    -drive file="$DISK_FILE",if=virtio,format=qcow2 \
    -cdrom "$ISO_FILE" \
    -boot order=d \
    -netdev user,id=net0 \
    -device virtio-net,netdev=net0 \
    -vnc "$VNC_DISPLAY" \
    -usb -device usb-tablet \
    -vga std &

  QEMU_PID=$!

  while true; do
    read -rp "👉 Gõ 'xong': " DONE
    if [ "$DONE" = "xong" ]; then
      touch "$FLAG_FILE"
      kill "$QEMU_PID" 2>/dev/null || true
      kill "$BORE_KEEPER_PID" 2>/dev/null || true
      pkill bore 2>/dev/null || true
      rm -f "$ISO_FILE"
      echo "✅ Done!"
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
    -drive file="$DISK_FILE",if=virtio,format=qcow2 \
    -boot order=c \
    -netdev user,id=net0 \
    -device virtio-net,netdev=net0 \
    -vnc "$VNC_DISPLAY" \
    -usb -device usb-tablet \
    -vga std
fi
