# Video cards. Intel and AMD work out of the box with the open drivers in the kernel; NVIDIA needs its own driver.
# scripts/new-host.sh detects the cards when a config is made and fills in my.intelGpu / my.nvidia for that config.
#
# Laptops with an Intel (or AMD) GPU plus an NVIDIA GPU ("hybrid graphics") use PRIME offload: everything runs on the
# economical built-in GPU, and the NVIDIA card is switched off when it is not used. Start a program on the NVIDIA
# card with:  nvidia-offload <program>   (e.g. nvidia-offload blender)
{ config, lib, pkgs, ... }:

let
  cfg = config.my.nvidia;
  hybrid = cfg.prime.nvidiaBusId != "" && (cfg.prime.intelBusId != "" || cfg.prime.amdgpuBusId != "");
in
{
  options.my.intelGpu = lib.mkEnableOption "hardware video acceleration for an Intel GPU (Broadwell or newer)";

  options.my.nvidia = {
    enable = lib.mkEnableOption "the NVIDIA driver";
    open = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Use NVIDIA's open kernel modules: right for Turing and newer (GTX 16xx, RTX, Quadro T/RTX and newer).
        Set to false for older cards (GTX 10xx and older, Quadro P/M).
      '';
    };
    prime = {
      intelBusId = lib.mkOption { type = lib.types.str; default = ""; example = "PCI:0:2:0"; description = "PCI address of the Intel GPU (hybrid laptops)."; };
      amdgpuBusId = lib.mkOption { type = lib.types.str; default = ""; example = "PCI:5:0:0"; description = "PCI address of the AMD GPU (hybrid laptops)."; };
      nvidiaBusId = lib.mkOption { type = lib.types.str; default = ""; example = "PCI:1:0:0"; description = "PCI address of the NVIDIA GPU (hybrid laptops)."; };
    };
  };

  config = lib.mkMerge [
    { hardware.graphics.enable = true; }

    (lib.mkIf config.my.intelGpu {
      # VA-API video decoding on the Intel GPU (lighter on the battery when watching videos)
      hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
    })

    (lib.mkIf cfg.enable {
      services.xserver.videoDrivers = [ "nvidia" ];
      hardware.nvidia = {
        modesetting.enable = true;
        open = cfg.open;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;
        powerManagement.enable = true;                  # suspend and resume
        powerManagement.finegrained = hybrid && cfg.open; # switch the NVIDIA card off when idle (Turing and newer)
        prime = lib.mkIf hybrid {
          offload.enable = true;
          offload.enableOffloadCmd = true;              # the command nvidia-offload
          intelBusId = cfg.prime.intelBusId;
          amdgpuBusId = cfg.prime.amdgpuBusId;
          nvidiaBusId = cfg.prime.nvidiaBusId;
        };
      };
      # The NVIDIA driver is unfree software
      my.allowedUnfree = [ "nvidia-x11" "nvidia-settings" "nvidia-persistenced" ];
    })
  ];
}
