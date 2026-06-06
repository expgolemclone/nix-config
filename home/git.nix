{ ... }:

{
  programs.git = {
    enable = true;
    signing.format = null;
    includes = [
      {
        condition = "gitdir:~/nix-config/";
        contents = {
          core.hooksPath = "~/nix-config/hooks";
        };
      }
    ];
    settings = {
      user.name = "exp";
      user.email = "nakanakananakada@gmail.com";
    };
  };
}
