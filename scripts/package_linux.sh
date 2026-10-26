#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:-0.1.0}"
arch=x86_64
bundle="$root/apps/devcat_flutter/build/linux/x64/release/bundle"
dist="$root/dist"
stage="$dist/linux-root"
mkdir -p "$stage/usr/lib/devcat" "$stage/usr/bin" "$stage/usr/share/applications" "$stage/usr/share/icons/hicolor/512x512/apps" "$stage/usr/share/licenses/devcat"
cp -a "$bundle/." "$stage/usr/lib/devcat/"
cp "$root/LICENSE" "$stage/usr/share/licenses/devcat/LICENSE"
cp "$root/packages/cat_assets/devcat.png" "$stage/usr/share/icons/hicolor/512x512/apps/devcat.png"
cat > "$stage/usr/bin/devcat" <<'LAUNCH'
#!/bin/sh
exec /usr/lib/devcat/devcat "$@"
LAUNCH
chmod 755 "$stage/usr/bin/devcat"
cat > "$stage/usr/share/applications/dev.devcat.DevCat.desktop" <<'DESKTOP'
[Desktop Entry]
Name=DevCat
Comment=Offline programming workshop
Exec=devcat
Icon=devcat
Terminal=false
Type=Application
Categories=Development;Education;
StartupWMClass=dev.devcat.devcat
DESKTOP
mkdir -p "$dist/DevCat-$version-linux-$arch"
cp -a "$bundle/." "$dist/DevCat-$version-linux-$arch/"
cp "$root/LICENSE" "$dist/DevCat-$version-linux-$arch/"
tar -C "$dist" -czf "$dist/DevCat-$version-linux-$arch.tar.gz" "DevCat-$version-linux-$arch"
mkdir -p "$stage/DEBIAN"
cat > "$stage/DEBIAN/control" <<CONTROL
Package: devcat
Version: $version
Section: education
Priority: optional
Architecture: amd64
Maintainer: DevCat contributors <student@devcat.local>
Depends: libgtk-3-0 (>= 3.22), libsecret-1-0, libgstreamer1.0-0, libgstreamer-plugins-base1.0-0, gstreamer1.0-plugins-good, libstdc++6
Description: Offline programming workshop with a pixel cat mentor
 Introductory lessons, generated exercises, a local editor and progress sync.
CONTROL
dpkg-deb --root-owner-group --build "$stage" "$dist/DevCat-$version-linux-amd64.deb"
rm -r "$stage/DEBIAN"
rpmdir="$dist/rpm-build"
mkdir -p "$rpmdir"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
cat > "$rpmdir/SPECS/devcat.spec" <<SPEC
Name: devcat
Version: $version
Release: 1
Summary: Offline programming workshop
License: MIT
URL: https://github.com/PANDORA615/DevCat-
BuildArch: x86_64
Requires: gtk3, libsecret, gstreamer1, gstreamer1-plugins-base, gstreamer1-plugins-good
AutoReqProv: no
%description
Introductory programming lessons and local code practice.
%install
mkdir -p %{buildroot}
cp -a "$stage/usr" %{buildroot}/
%files
/usr/bin/devcat
/usr/lib/devcat
/usr/share/applications/dev.devcat.DevCat.desktop
/usr/share/icons/hicolor/512x512/apps/devcat.png
/usr/share/licenses/devcat/LICENSE
SPEC
rpmbuild --define "_topdir $rpmdir" -bb "$rpmdir/SPECS/devcat.spec"
cp "$rpmdir/RPMS/x86_64/"*.rpm "$dist/DevCat-$version-linux-x86_64.rpm"
archroot="$dist/arch-root"
mkdir -p "$archroot"
cp -a "$stage/usr" "$archroot/"
cat > "$archroot/.PKGINFO" <<PKG
pkgname = devcat
pkgbase = devcat
pkgver = $version-1
pkgdesc = Offline programming workshop
url = https://github.com/PANDORA615/DevCat-
builddate = $(date +%s)
packager = DevCat contributors
size = $(du -sb "$stage/usr" | cut -f1)
arch = x86_64
license = MIT
depend = gtk3
depend = libsecret
depend = gstreamer
depend = gst-plugins-base-libs
depend = gst-plugins-good
PKG
tar --zstd --owner=0 --group=0 -C "$archroot" -cf "$dist/DevCat-$version-linux-x86_64.pkg.tar.zst" .PKGINFO usr
appdir="$dist/DevCat.AppDir"
mkdir -p "$appdir/usr/lib"
cp -a "$stage/usr/lib/devcat" "$appdir/usr/lib/"
cp "$stage/usr/share/applications/dev.devcat.DevCat.desktop" "$appdir/devcat.desktop"
cp "$root/packages/cat_assets/devcat.png" "$appdir/devcat.png"
cat > "$appdir/AppRun" <<'APPRUN'
#!/bin/sh
appdir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$appdir/usr/lib/devcat/devcat" "$@"
APPRUN
chmod 755 "$appdir/AppRun"
# Flutter and plugin binaries are included. GTK/GStreamer/Secret Service remain OS dependencies.
curl --fail --location --retry 3 https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage -o "$dist/appimagetool"
chmod +x "$dist/appimagetool"
ARCH=x86_64 "$dist/appimagetool" --appimage-extract-and-run "$appdir" "$dist/DevCat-$version-linux-x86_64.AppImage"
