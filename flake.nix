{
  description = "Dev env for building Lineage OS for vili (Xiaomi 11T Pro)";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    
    # Device-specific repositories with shallow cloning, change if desired
    device-sm8350-common = {
      url = "github:AOSP-for-vili/device_xiaomi_sm8350-common/lineage-22.2?shallow=1";
      flake = false;
    };
    kernel-sm8350 = {
      url = "github:AOSP-for-vili/android_kernel_xiaomi_sm8350/lineage-22.1?shallow=1";
      flake = false;
    };
    hardware-xiaomi = {
      url = "github:AOSP-for-vili/android_hardware_xiaomi/lineage-22.2?shallow=1";
      flake = false;
    };
    vendor-vili = {
      url = "github:AOSP-for-vili/vendor_xiaomi_vili/lineage-22.2?shallow=1";
      flake = false;
    };
    vendor-sm8350-common = {
      url = "github:AOSP-for-vili/vendor_xiaomi_sm8350-common/lineage-22.2?shallow=1";
      flake = false;
    };
    vendor-vili-firmware = {
      url = "gitlab:0mar99/vendor-xiaomi-vili-firmware/main?shallow=1";
      flake = false;
    };
    device-vili = {
      url = "github:FrederikRichter/device_xiaomi_vili/lineage-22.2?shallow=1";
      flake = false;
    };
  };


  outputs = { self, nixpkgs, flake-utils, device-sm8350-common, kernel-sm8350, 
              hardware-xiaomi, vendor-vili, vendor-sm8350-common, 
              vendor-vili-firmware, device-vili, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = nixpkgs.lib;

        # Change these if you encounter rate limiting or swapping
        JOBS_NETWORK = "8";
        JOBS_CHECKOUT = "$(nproc --all)";

        LINEAGE-ANROID-REV = "88f76658b2497b7ee02d2af605fabd7baea443f4";
        # LINEAGE-ANROID-REV = "lineage-22.2";

        sourceScript = pkgs.writeTextFile {
          name = "setup_source";
          text = ''
            #!${pkgs.bashInteractive}/bin/bash

            echo "Setting up source directory..."

            # Create or ensure ownership of Source directory
            if [ ! -d "Source" ]; then 
              mkdir -p Source
            fi

            cd Source
            
            if [ ! -d .repo ]; then
              echo "Setting up .repo directory using fetched LineageOS repository..."
              mkdir -p .repo
              
              # Initialize repo using the fetched LineageOS manifest locally.
              ${pkgs.git-repo}/bin/repo init -u https://github.com/LineageOS/android.git -b ${LINEAGE-ANROID-REV} --git-lfs
            else
              echo "repo already initialized"
            fi

            # Run a minimal repo sync to fetch core LineageOS repositories
            echo "Running minimal repo sync for core LineageOS repositories..."
            ${pkgs.git-repo}/bin/repo sync --current-branch --jobs-network=${JOBS_NETWORK} --jobs-checkout=${JOBS_CHECKOUT}

            echo "Setting up repositories from flake inputs directly..."
            
            # Updated copy_input that expects source first, target second.
            copy_input() {
              local source="$1"
              local target_dir="$2"
              
              mkdir -p "$(dirname "$target_dir")"
              
              if [ -d "$target_dir" ]; then
                echo "Removing existing $target_dir..."
                rm -rf "$target_dir"
              fi
              
              echo "Copying $source to $target_dir..."
              cp -r "$source" "$target_dir"
            }
            
            # Copy all device-specific repositories directly from flake inputs
            copy_input "${device-sm8350-common}" "device/xiaomi/sm8350-common"
            copy_input "${kernel-sm8350}" "kernel/xiaomi/sm8350"
            copy_input "${hardware-xiaomi}" "hardware/xiaomi"
            copy_input "${vendor-vili}" "vendor/xiaomi/vili"
            copy_input "${vendor-sm8350-common}" "vendor/xiaomi/sm8350-common"
            copy_input "${vendor-vili-firmware}" "vendor/xiaomi/vili-firmware"
            copy_input "${device-vili}" "device/xiaomi/vili"


            # make files writeable since they are copied from nix store
            chmod -R u+w ./*
          '';
          executable = true;
          destination = "/bin/setup_source";
        };

        buildScript = pkgs.writeTextFile {
          name = "start_build";
          text = ''
            #!${pkgs.bashInteractive}/bin/bash
            if [ -d "Source" ]; then
              cd Source || exit
              echo "Entered Source Directory"
            else
              echo "Source directory does not exist"
              exit 1
            fi
            source ./build/envsetup.sh 
            build_build_var_cache
            brunch vili
          '';
          executable = true;
          destination = "/bin/start_build";
        };

        fhsEnv = pkgs.buildFHSEnv {
          name = "LOS22_2-env";
          targetPkgs = pkgs: (with pkgs; [
            bison git-repo ccache gcc git bashInteractive git-lfs gnupg gperf wget
            readline libz libelf lz4 openssl m4 ncurses5 libxml2 lzop
            schedtool squashfsTools libxslt zip unzip libxcrypt-legacy
            zlib python3 gnumake pkg-config bc libgcc
            bash-completion gnupatch coreutils
            psmisc flex fontconfig nettools imagemagick android-tools
            libelf procps freetype pngcrush rsync ncurses dejavu_fonts
          ]) ++ [ sourceScript buildScript ];

          profile = ''
            # Setting Release Target
            export TARGET_RELEASE=ap4a
            
            # ignore ssh config
            export GIT_SSH_COMMAND="ssh -F /dev/null"
            export GIT_SSH=ssh

            # New Commands Message
            echo "New Commands: start_build, setup_source"
          '';
        };

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [ fhsEnv ];
          shellHook = ''
            echo "Entering FHS environment..."
            exec ${fhsEnv}/bin/LOS22_2-env
          '';
        };

        packages.fhsEnv = fhsEnv;
      }
    );
}
