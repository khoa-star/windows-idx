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
RDP_PORT="3389"

FLAG_FILE="installed.flag"
WORKDIR="$HOME/windows-idx"

### NGROK ###
NGROK_TOKEN="39b3jTZdvMRcYqsJpvutZzASzuR_31eximZ1Tg5Bn91ky4gwu"
NGROK_DIR="$HOME/.ngrok"
NGROK_BIN="$NGROK_DIR/ngrok"
NGROK_CFG="$NGROK_DIR/ngrok.yml"
NGROK_LOG="$NGROK_DIR/ngrok.log"

### DISCORD WEBHOOK ###
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/1470356599464919136/XmdBlWXAQN-qO-13q_ABLHPTgo54c6TAepCBALSa49BLW6dwu1Shw2929382846N40"
SEND_DISCORD="${SEND_DISCORD:-1}"

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

############################
# BACKGROUND FILE CREATOR #
############################
(
  while true; do
    echo "Windows Info" > windowsinfo.txt
    sleep 300
  done
) &
FILE_PID=$!

#################
# NGROK START  #
#################
mkdir -p "$NGROK_DIR"

if [ ! -f "$NGROK_BIN" ]; then
  curl -sL https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz \
    | tar -xz -C "$NGROK_DIR"
  chmod +x "$NGROK_BIN"
fi

# Add authtoken trực tiếp
"$NGROK_BIN" config add-authtoken "$NGROK_TOKEN"

cat > "$NGROK_CFG" <<EOF
version: "2"
tunnels:
  vnc:
    proto: tcp
    addr: 5900
  rdp:
    proto: tcp
    addr: 3389
EOF

pkill -f "$NGROK_BIN" 2>/dev/null || true
"$NGROK_BIN" start --all --config "$NGROK_CFG" --log=stdout > "$NGROK_LOG" 2>&1 &

#################
# GET NGROK URL #
#################

get_ngrok_url() {
  python3 - "$1" <<'PY'
import json, sys, urllib.request
name = sys.argv[1]
try:
    data = urllib.request.urlopen("http://127.0.0.1:4040/api/tunnels", timeout=2).read()
    j = json.loads(data.decode("utf-8"))
    for t in j.get("tunnels", []):
        if t.get("name") == name:
            print(t.get("public_url",""))
            raise SystemExit(0)
except Exception:
    pass
print("")
PY
}

VNC_ADDR=""
RDP_ADDR=""
for _ in {1..25}; do
  VNC_ADDR="$(get_ngrok_url vnc)"
  RDP_ADDR="$(get_ngrok_url rdp)"
  if [[ -n "$VNC_ADDR" && -n "$RDP_ADDR" ]]; then
    break
  fi
  sleep 0.4
done

echo "🌍 VNC PUBLIC : $VNC_ADDR"
echo "🌍 RDP PUBLIC : $RDP_ADDR"

#################
# DISCORD SEND #
#################

send_discord() {
  [[ "$SEND_DISCORD" = "1" ]] || return 0
  [[ -n "$DISCORD_WEBHOOK_URL" ]] || return 0
  curl -sS -H "Content-Type: application/json" \
    -X POST \
    -d "{\"content\":\"VNC: $VNC_ADDR\nRDP: $RDP_ADDR\"}" \
    "$DISCORD_WEBHOOK_URL" >/dev/null || true
}

send_discord

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
    -netdev user,id=net0,hostfwd=tcp::3389-:3389 \
    -device e1000,netdev=net0 \
    -vnc "$VNC_DISPLAY" \
    -usb -device usb-tablet &

  QEMU_PID=$!

  while true; do
    read -rp "👉 Nhập 'xong': " DONE
    if [ "$DONE" = "xong" ]; then
      touch "$FLAG_FILE"
      kill "$QEMU_PID"
      kill "$FILE_PID"
      pkill -f "$NGROK_BIN"
      rm -f "$ISO_FILE"
      exit 0
    fi
  done

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
    -usb -device usb-tablet

fi
