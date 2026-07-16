{
  description = "NixOS system configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    yazi-fork = {
      url = "git+file:///home/exp/projects/yazi_fork";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, nixvim, yazi-fork, ... }: {
    # Native NixOS
    nixosConfigurations."nixos" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./modules/external-hdd-backup.nix
        ./modules/external-hdd-backup-initrd.nix
        ./modules/gc.nix
        ./hosts/nixos/configuration.nix
        home-manager.nixosModules.home-manager
        {
          nixpkgs.overlays = [ yazi-fork.overlays.default ];
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
          home-manager.users.exp = import ./home/home.nix;
          home-manager.extraSpecialArgs = {
            inherit nixvim;
          };
        }
      ];
    };
  };
}
