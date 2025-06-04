{
  clangStdenv,
  lib,
  fetchurl,
  pkg-config,
  cmake,
  perl,
  python3,
  ruby,
  glib,
  harfbuzzFull,
  libjpeg,
  libepoxy,
  libgcrypt,
  libgpg-error,
  libtasn1,
  libxkbcommon,
  libxml2,
  libpng,
  sqlite,
  unifdef,
  libwebp,
  libwpe,
  gobject-introspection,
  gi-docgen,
  libsoup_3,
  libsysprof-capture,
  pcre2,
  atkmm,
  flite,
  libjxl,
  woff2,
  libxslt,
  libavif,
  systemd,
  lcms,
  libdrm,
  libgbm,
  libbacktrace,
  libseccomp,
  bubblewrap,
  xdg-dbus-proxy,
  gst_all_1,
  gperf,
  freetype,
  fontconfig,
  openxr-loader,
  replaceVars,
  addDriverRunpath,
  openssl_3,
  testers,
  systemdSupport ? lib.meta.availableOn clangStdenv.hostPlatform systemd,
}:
clangStdenv.mkDerivation (finalAttrs: rec {
  pname = "wpewebkit";
  version = "2.49.2";

  outputs = [
    "out"
    "dev"
    "devdoc"
  ];

  # https://github.com/NixOS/nixpkgs/issues/153528
  # Can't be linked within a 4GB address space.
  separateDebugInfo = clangStdenv.hostPlatform.isLinux && !clangStdenv.hostPlatform.is32bit;

  src = fetchurl {
    url = "https://wpewebkit.org/releases/wpewebkit-${version}.tar.xz";
    sha256 = "sha256-ITT4WI/Fw6GjogOWmOi8GjldJGmXaAOj3gSPsclgGBU=";
  };

  patches = lib.optionals clangStdenv.hostPlatform.isLinux [
    (replaceVars ./fix-bubblewrap-paths.patch {
      inherit (builtins) storeDir;
      inherit (addDriverRunpath) driverLink;
    })
  ];

  cmakeFlags =
    [
      "-DENABLE_INTROSPECTION=ON"
      "-DPORT=WPE"
      "-DUSE_LIBSECRET=ON"
      "-DENABLE_EXPERIMENTAL_FEATURES=ON"
      # Have to be explicitly specified when cross.
      # https://github.com/WebKit/WebKit/commit/a84036c6d1d66d723f217a4c29eee76f2039a353
      "-DBWRAP_EXECUTABLE=${lib.getExe bubblewrap}"
      "-DDBUS_PROXY_EXECUTABLE=${lib.getExe xdg-dbus-proxy}"
    ]
    ++ lib.optionals (!systemdSupport) [
      "-DENABLE_JOURNALD_LOG=OFF"
    ];
  nativeBuildInputs = [
    cmake
    gobject-introspection
    gperf
    perl
    perl.pkgs.FileCopyRecursive # used by copy-user-interface-resources.pl
    pkg-config
    python3
    ruby
    gi-docgen
    glib # for gdbus-codegen
    unifdef
  ];
  buildInputs = [
    harfbuzzFull
    libjpeg
    libepoxy
    libgcrypt
    libgpg-error
    libtasn1
    libxkbcommon
    libxml2
    libpng
    sqlite
    libwebp
    libwpe
    libsoup_3
    libsysprof-capture
    pcre2
    atkmm
    flite
    libjxl
    woff2
    libxslt
    libavif
    systemd
    lcms
    libdrm
    libgbm
    libbacktrace
    libseccomp
    bubblewrap
    xdg-dbus-proxy
    gst_all_1.gst-plugins-base.dev
    gst_all_1.gst-plugins-bad.dev
    freetype
    fontconfig
    openxr-loader
    openssl_3
  ];
  postPatch = ''
    patchShebangs .
  '';

  postFixup = ''
    # Cannot be in postInstall, otherwise _multioutDocs hook in preFixup will move right back.
    moveToOutput "share/doc" "$devdoc"
  '';

  requiredSystemFeatures = ["big-parallel"];

  passthru.tests.pkg-config = testers.testMetaPkgConfig finalAttrs.finalPackage;

  meta = with lib; {
    description = "WPE WebKit";
    license = licenses.bsd2;
    homepage = "https://wpewebkit.org";
    maintainers = with maintainers; [matthewbauer];
    platforms = platforms.linux;
  };
})
