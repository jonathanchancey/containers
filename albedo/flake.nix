{
  description = "bastille's albedo container";

  inputs = {
    albedo.url = "git+https://tangled.org/okami.mom/albedo?rev=a65e5babc2b9fade663826a5034e9e4728426f89";
    nixpkgs.follows = "albedo/nixpkgs";
  };

  outputs =
    {
      self,
      albedo,
      nixpkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      package = albedo.packages.${system}.default;
      healthcheck = pkgs.writeScriptBin "albedo-healthcheck" ''
        #!${pkgs.python3}/bin/python3
        ${builtins.readFile ./healthcheck.py}
      '';
      entrypoint = pkgs.writeShellScriptBin "albedo-container" ''
        set -eu
        # discovery records describe the old pid/network namespace, not durable state.
        # each home must belong to only one container; retain locks and sign-in keys.
        ${pkgs.coreutils}/bin/rm -f "$ALBEDO_HOME/daemon.json" "$ALBEDO_HOME/web.json"
        # --serve stays in the foreground without logging the sign-in key.
        exec ${package}/bin/albedo web --serve --local --no-open
      '';
    in
    {
      packages.${system} = {
        default = self.packages.${system}.image;
        image = pkgs.dockerTools.buildLayeredImage {
          name = "ghcr.io/jonathanchancey/albedo";
          tag = "a65e5babc2b9-1";
          contents = [
            package
            healthcheck
            entrypoint
            pkgs.bashInteractive
            pkgs.coreutils
            pkgs.curl
            pkgs.git
            pkgs.kubectl
            pkgs.procps
            pkgs.python3
            pkgs.ripgrep
            pkgs.cacert
            pkgs.dockerTools.fakeNss
          ];
          extraCommands = ''
            mkdir -p home/albedo tmp
            chmod 1777 tmp
          '';
          fakeRootCommands = ''
            chown -R 1000:1000 home/albedo
          '';
          config = {
            User = "1000:1000";
            WorkingDir = "/home/albedo";
            Cmd = [ "/bin/albedo-container" ];
            Env = [
              "HOME=/home/albedo"
              "ALBEDO_HOME=/home/albedo/.albedo"
              "ALBEDO_PORT=4318"
              "PATH=/bin"
              "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
              "TZDIR=${pkgs.tzdata}/share/zoneinfo"
            ];
            Labels = {
              "org.opencontainers.image.source" = "https://github.com/jonathanchancey/containers";
              "org.opencontainers.image.description" = "albedo with kubernetes inspection tools";
              "org.opencontainers.image.licenses" = "MPL-2.0";
            };
          };
        };
      };
      apps.${system}.skopeo = {
        type = "app";
        program = "${pkgs.skopeo}/bin/skopeo";
      };
      formatter.${system} = pkgs.nixfmt;
    };
}
