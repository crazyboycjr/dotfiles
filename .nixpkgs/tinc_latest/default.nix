{ lib, stdenv, fetchurl, meson, ninja, pkg-config, texinfo, ncurses, lz4, vde2, cmocka, zlib, lzo, openssl }:

stdenv.mkDerivation rec {
  pname = "tinc";
  version = "latest"; # June 5

  src = fetchurl {
    url = "https://github.com/gsliepen/tinc/archive/refs/tags/latest.tar.gz";
    sha256 = "cbcceca54d6ffaac2fe37675ed5cf1d38a892630ad3ffb28c7eac27a2822d5be";
  };

  outputs = [ "out" "man" "info" ];

  nativeBuildInputs = [ meson ninja texinfo pkg-config ];
  buildInputs = [ ncurses zlib lzo openssl lz4 vde2 cmocka ];

  # Fix the bug for sssp. Keep it until the upstream have fixed it.
  patches = [ ./sssp.patch ];

  mesonBuildType = "release";

  mesonFlags = [
    "-Dtunemu=disabled"
    "-Dreadline=disabled"
  ];

  meta = with lib; {
    description = "VPN daemon with full mesh routing";
    longDescription = ''
      tinc is a Virtual Private Network (VPN) daemon that uses tunnelling and
      encryption to create a secure private network between hosts on the
      Internet.  It features full mesh routing, as well as encryption,
      authentication, compression and ethernet bridging.
    '';
    homepage="http://www.tinc-vpn.org/";
    license = licenses.gpl2Plus;
    platforms = platforms.unix;
    maintainers = with maintainers; [ lassulus mic92 crazyboycjr ];
  };
}
