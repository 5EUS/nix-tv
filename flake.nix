{
  description = "Plasma Bigscreen TV box on a salvaged laptop motherboard";

  inputs = {
    # Bigscreen's Plasma 6 revival landed in nixpkgs well after 26.05 branched.
    # Check before you commit to stable:
    #   nix eval nixpkgs#kdePackages.plasma-bigscreen.version
    #   nix eval github:NixOS/nixpkgs/nixos-26.05#kdePackages.plasma-bigscreen.version
    # If stable still shows 5.27.x, stay on unstable for this host.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, ... }: {
    nixosConfigurations.tv = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./disko.nix
        ./configuration.nix
      ];
    };
  };
}
