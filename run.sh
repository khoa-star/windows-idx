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
NGROK_TOKEN=""
NGROK_DIR="$HOME/.ngrok"
NGROK_BIN="$NGROK_DIR/ngrok"
NGROK_CFG="$NGROK_DIR/ngrok.yml"
NGROK_LOG="$NGROK_DIR/ngrok.log"

### DISCORD WEBHOOK (THÊM) ###
# Dán webhook URL của Discord vào đây (Settings -> Integrations -> Webhooks)
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/1470356599464919136/XmdBlWXAQN-qO-13q_ABLHPTgo54c6TAepCBALSa49BLW6dwu1Shw2929382846N40"  # hoặc set env DISCORD_WEBHOOK_URL
SEND_DISCORD="${SEND_DISCORD:-1}"               # 1=send, 0=off

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
    echo "[$(date '+%H:%M:%S')] Đã tạo windowsinfo.txt"
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

cat > "$NGROK_CFG" <<EOF
version: "2"
authtoken: $NGROK_TOKEN
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

# ---- FIX: LẤY URL THEO TÊN TUNNEL QUA NGROK API (KHÔNG BỊ ĐẢO) ----
get_ngrok_url() {
  # $1 = tunnel name (vnc|rdp)
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

# chờ ngrok api lên và tunnel ready
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

if [[ -z "$VNC_ADDR" || -z "$RDP_ADDR" ]]; then
  echo "❌ Không lấy được public_url từ ngrok API."
  echo "👉 Mở log để xem: $NGROK_LOG"
  # fallback cuối cùng (có thể vẫn đảo, nhưng còn hơn trống)
  RDP_ADDR="$(grep -oE 'tcp://[^ ]+' "$NGROK_LOG" | sed -n '1p' || true)"
  VNC_ADDR="$(grep -oE 'tcp://[^ ]+' "$NGROK_LOG" | sed -n '2p' || true)"
fi

echo "🌍 VNC PUBLIC : $VNC_ADDR"
echo "🌍 RDP PUBLIC : $RDP_ADDR"

# ---- THÊM: GỬI DISCORD WEBHOOK ----
send_discord() {
  local msg="$1"
  [[ "$SEND_DISCORD" = "1" ]] || return 0
  [[ -n "$DISCORD_WEBHOOK_URL" ]] || return 0
  # escape JSON đơn giản
  local payload
  payload="$(python3 - <<PY
import json
print(json.dumps({"content": "$msg"}))
PY
)"
  curl -sS -H "Content-Type: application/json" -X POST \
    -d "$payload" "$DISCORD_WEBHOOK_URL" >/dev/null || true
}

send_discord "✅ NGROK TCP TUNNELS\n🖥️ VNC: $VNC_ADDR\n🧩 RDP: $RDP_ADDR\n📄 Log: $NGROK_LOG"

#################
# RUN QEMU     #
#################
if [ ! -f "$FLAG_FILE" ]; then
  echo "⚠️  CHẾ ĐỘ CÀI ĐẶT WINDOWS"
  echo "👉 Cài xong quay lại nhập: xong"

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
      echo "✅ Hoàn tất – lần sau boot thẳng qcow2"
      exit 0
    fi
  done

else
  echo "✅ Windows đã cài – boot thường"

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
