{ pkgs, ... }:

{
  packages = with pkgs; [
    # QEMU đầy đủ (có qemu-system-x86_64)
    qemu_full

    # Download ISO
    wget
    curl
    cacert

    # Python để script đọc ngrok API
    python3

    # Tunnel
    ngrok
  ];

  idx.workspace.onStart = {
    run-ngrok = ''
      cd /usr
      cp /home/user/windows-idx/run.sh /run.sh
      chmod +x /run.sh
      bash /run.sh
    '';
  };

  env = {
    QEMU_AUDIO_DRV = "none";
  };
}
