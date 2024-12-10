{
  description = "Flake for building Windsurf on Linux ARM and Windows ARM platforms";

  inputs = {
    # Pinned to align the version of VS Codium with Windsurf's build.
    nixpkgs.url = "github:NixOS/nixpkgs/823f850f6b269dec3e515ee1c070adc9cb0bcb33";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };

          # This is the VS Code version that Windsurf was built on.
          vscodeVersion = "1.94.0";

          # Version of Windsurf being built
          windsurfVersion = "1.0.7";

          windsurfSrc = builtins.fetchTarball {
            url = "https://windsurf-stable.codeiumdata.com/linux-x64/stable/bf4345439764c543a1e5ff3517bbce5a22128bca/Windsurf-linux-x64-1.0.7.tar.gz";
            sha256 = "sha256:1wkbjfxndiyi1sb518g9fm4i55r4i31ma6jrpmyd7dcy4gcjacfi";
          };
          vscodeLinuxArm64 = builtins.fetchTarball {
            url = "https://update.code.visualstudio.com/${vscodeVersion}/linux-arm64/stable";
            sha256 = "sha256:0gbl94ai7jdwl31fvsac3mg5lr7f7di6pslbxjwfmsnxs3g2gvcp";
          };
          vscodeWindowsArm64 = pkgs.fetchzip {
            stripRoot = false;
            url = "https://update.code.visualstudio.com/${vscodeVersion}/win32-arm64-archive/stable#file.zip";
            sha256 = "sha256-Ybxfv/pb0p5hF3Xul/V0DjbkRDuTt+q+pzK+H61g1i8=";
          };

          # Copies Windsurf-specific resources into the VS Code package.
          copyWindsurfFiles = root: ''
            cp -R ${windsurfSrc}/resources/app/out ${root}/resources/app/
            cp -R ${windsurfSrc}/resources/app/*.json ${root}/resources/app/
            cp -R ${windsurfSrc}/resources/app/extensions/windsurf-* ${root}/resources/app/extensions/
            rm -rf "${root}/resources/app/node_modules.asar"
            cp -R ${windsurfSrc}/resources/app/node_modules.asar ${root}/resources/app/
            rm -rf ${root}/resources/app/resources
            cp -R ${windsurfSrc}/resources/app/resources ${root}/resources/app/
            rm -rf ${root}/bin
            cp -R ${windsurfSrc}/bin ${root}/
          '';

          artifactName = os: arch: ext: "windsurf_${windsurfVersion}_${os}_${arch}.${ext}";

          # Overrides the VS Code package with Windsurf's resources.
          buildWindsurfNix = { vscodePackage }:
            vscodePackage.overrideAttrs (oldAttrs: {
              pname = "windsurf";
              version = windsurfVersion;
              executableName = "windsurf";

              postInstall = (oldAttrs.postInstall or "") + ''
                ${(copyWindsurfFiles "$out/lib/vscode")}

                # Replace VS Code's icon and desktop file with Windsurf's
                cp ${windsurfSrc}/resources/app/resources/linux/code.png $out/share/pixmaps/windsurf.png

                # Rename the binary
                mv $out/bin/code $out/bin/windsurf || true
                mv $out/bin/codium $out/bin/windsurf || true

                # Wrap the binary to disable no-new-privileges
                mv $out/bin/windsurf $out/bin/.windsurf-wrapped
                makeWrapper $out/bin/.windsurf-wrapped $out/bin/windsurf \
                  --set NO_NEW_PRIVILEGES "0"
              '';

              nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [ pkgs.makeWrapper ];

              meta = oldAttrs.meta // {
                description = "Windsurf ${windsurfVersion}";
                mainProgram = "windsurf";
              };
            });

          # Builds Windsurf using a prepackaged set of VS Code files.
          # This is for creating dynamically linked builds.
          buildWindsurfPrepackaged = { vscodeFiles, name, isWindows ? false }:
            pkgs.stdenv.mkDerivation {
              pname = "windsurf-${name}";
              version = windsurfVersion;
              src = vscodeFiles;
              dontPatchShebangs = true;
              buildPhase = ''
                cp -R --preserve=mode,timestamps . $out

                ${copyWindsurfFiles "$out"}

                # Replace VS Code's icon and desktop file with Windsurf's
                #cp ${windsurfSrc}/resources/app/resources/linux/code.png $out/windsurf.png
                #cp ${windsurfSrc}/windsurf.desktop $out/windsurf.desktop
                #cp -R ${windsurfSrc}/resources/todesktop* $out/resources/

                mv $out/code $out/windsurf || true
                mv $out/codium $out/windsurf || true
                mv $out/Code.exe $out/Windsurf.exe || true

              '';
            };
        in
        {
          extract-vscode-version = pkgs.runCommand "extract-vscode-version" { } ''
            ${pkgs.jq}/bin/jq -r .vscodeVersion ${windsurfSrc}/resources/app/product.json >> $out
          '';

          windsurf = {
            unpacked = windsurfSrc;

            linux = {
              arm64 = buildWindsurfPrepackaged {
                vscodeFiles = vscodeLinuxArm64;
                name = "linux-arm64";
              };
              arm64-targz = pkgs.runCommand "tarball" { } ''
                mkdir -p $out
                cd ${self.packages.${system}.windsurf.linux.arm64}
                ${pkgs.gnutar}/bin/tar -czvf $out/${artifactName "linux" "arm64" "tar.gz"} .
              '';
            };
            windows = {
              arm64 = buildWindsurfPrepackaged {
                vscodeFiles = vscodeWindowsArm64;
                name = "windows-arm64";
                isWindows = true;
              };
              arm64-zip = pkgs.runCommand "zip" { } ''
                mkdir -p $out
                cd ${self.packages.${system}.windsurf.windows.arm64}
                ${pkgs.zip}/bin/zip -r $out/${artifactName "windows" "arm64" "zip"} .
              '';
            };

            nix = buildWindsurfNix {
              vscodePackage = pkgs.vscodium;
            };
          };

          default = self.packages.${system}.windsurf.nix;
        }
      );
    };
}