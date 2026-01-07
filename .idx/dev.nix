{ pkgs, ... }:

{
  # Danh sách package cài sẵn
  packages = with pkgs; [
    # QEMU đầy đủ (có qemu-system-x86_64)
    qemu_full

    # Network / download
    curl
    wget

    # Tunnel
    ngrok

    # Dev tools
    git
    unzip
    
  ];

  # Biến môi trường (an toàn với IDX)
  env = {
    QEMU_AUDIO_DRV = "none";
  };
}
