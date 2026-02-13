#!/usr/bin/env bash
set -e

### CONFIG ###
ISO_URL="https://go.microsoft.com/fwlink/p/?LinkID=2195443"
ISO_FILE="win11-gamer.iso"

DISK_FILE="/var/win11.qcow2"
DISK_SIZE="100G"

RAM="16G"
CORES="8"

VNC_DISPLAY=":0"

FLAG_FILE="installed.flag"
WORKDIR="$HOME/windows-idx"

### NGROK ###
NGROK_TOKEN="39b3jTZdvMRcYqsJpvutZzASzuR_31eximZ1Tg5Bn91ky4gwu"
NGROK_DIR="$HOME/.ngrok"
NGROK_BIN="$NGROK_DIR/ngrok"

### DISCORD ###
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/1470356599464919136/XmdBlWXAQN-qO-13q_ABLHPTgo54c6TAepCBALSa49BLW6dwu1Shw2929382846N40"

### CHECK ###
[ -e /dev/kvm ] || { echo "❌ No /dev/kvm"; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { echo "❌ No qemu"; exit 1; }

### PREP ###
mkdir -p "$WORKDIR"
cd "$WORKDIR"

[ -f "$DISK_FILE" ] || qemu-img create -f qcow2 "$DISK_FILE" "$DISK_SIZE"

if [ ! -f "$FLAG_FILE" ]; then
  [ -f "$ISO_FILE" ] || wget --no-check-certificate -O "$ISO_FILE" "$ISO_URL"
fi

#################
# START QEMU   #
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
    -netdev user,id=net0,hostfwd=tcp::3389-:3389 \
    -device e1000,netdev=net0 \
    -vnc "$VNC_DISPLAY" \
    -usb -device usb-tablet &
else
  qemu-system-x86_64 \
    -enable-kvm \
    -cpu host \
    -smp "$CORES" \
    -m "$RAM" \
    -machine q35 \
    -drive file="$DISK_FILE",if=ide,format=qcow2 \
    -boot order=c \
    -netdev user,id=net0,hostfwd=tcp::3389-:3389 \
    -device e1000,netdev=net0 \
    -vnc "$VNC_DISPLAY" \
    -usb -device usb-tablet &
fi

sleep 8

#################
# START NGROK  #
#################

mkdir -p "$NGROK_DIR"

if [ ! -f "$NGROK_BIN" ]; then
  curl -sL https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz \
    | tar -xz -C "$NGROK_DIR"
  chmod +x "$NGROK_BIN"
fi

"$NGROK_BIN" config add-authtoken "$NGROK_TOKEN"

pkill -f "$NGROK_BIN" 2>/dev/null || true

"$NGROK_BIN" tcp 5900 > "$NGROK_DIR/vnc.log" 2>&1 &
"$NGROK_BIN" tcp 3389 > "$NGROK_DIR/rdp.log" 2>&1 &

sleep 6

#################
# GET URL      #
#################

TUNNELS_JSON=$(curl -s http://127.0.0.1:4040/api/tunnels)

VNC_ADDR=$(echo "$TUNNELS_JSON" | grep 5900 | grep -o 'tcp://[^"]*')
RDP_ADDR=$(echo "$TUNNELS_JSON" | grep 3389 | grep -o 'tcp://[^"]*')

echo ""
echo "🌍 VNC PUBLIC : $VNC_ADDR"
echo "🌍 RDP PUBLIC : $RDP_ADDR"
echo ""

#################
# DISCORD SEND #
#################

curl -sS -H "Content-Type: application/json" \
  -X POST \
  -d "{\"content\":\"VNC: $VNC_ADDR\nRDP: $RDP_ADDR\"}" \
  "$DISCORD_WEBHOOK_URL" >/dev/null || true

wait
