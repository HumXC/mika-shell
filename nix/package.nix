{
  lib,
  makeWrapper,
  pkg-config,
  buildGoModule,
  glib-networking,
  gsettings-desktop-schemas,
  gtk3,
  webkitgtk_4_1,
  libwebp,
  gtk-layer-shell,
  debug ? false,
}:
buildGoModule {
  pname = "mikami";
  version = "0.0.1";

  src = ./..;

  vendorHash = "sha256-llc4U53wr/5erDBIPpbZhlQkQVGcHr/vlfEQkzOWe44=";
  nativeBuildInputs = [makeWrapper pkg-config];
  proxyVendor = true;
  allowGoReference = true;
  buildInputs = [webkitgtk_4_1 gtk-layer-shell libwebp];
  tags =
    [
      "desktop"
      "production"
    ]
    ++ (lib.optional debug ["debug"]);
  ldflags = [
    "-s"
    "-w"
  ];

  # https://wails.io/docs/guides/nixos-font/
  postFixup = ''
    wrapProgram $out/bin/mikami \
      --set XDG_DATA_DIRS ${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}:${gtk3}/share/gsettings-schemas/${gtk3.name}:$XDG_DATA_DIRS \
      --set GIO_MODULE_DIR ${glib-networking}/lib/gio/modules/
  '';
  meta = {
    description = "Build display manager using HTML + CSS + JS";
    homepage = "https://github.com/HumXC/mikami";
    license = lib.licenses.mit;
    mainProgram = "html-greet";
    platforms = lib.platforms.unix;
  };
}
