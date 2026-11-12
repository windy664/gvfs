#!/usr/bin/env bash
# 为 gvfs 的 FTP 后端编译 charset 支持，并部署到用户目录（不需要 root）
set -euo pipefail

SRC_DIR="${1:-$HOME/.cache/gvfs-src}"
PREFIX="$HOME/.local"
VENV="$HOME/.local/share/gvfs-build-venv"
MOUNTS="$PREFIX/share/gvfs/mounts"
LIBEXEC="$PREFIX/libexec/gvfs"

echo "==> 获取 gvfs 1.62.0 源码"
if [ ! -d "$SRC_DIR" ]; then
  git clone --depth 1 --branch 1.62.0 https://github.com/GNOME/gvfs.git "$SRC_DIR"
fi

echo "==> 准备构建工具"
if [ ! -x "$VENV/bin/meson" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install meson ninja
fi

echo "==> 打补丁"
cd "$SRC_DIR"
git apply --check "$(dirname "$0")/../gvfs-1.62.0-ftp-charset.patch" 2>/dev/null \
  || git apply "$(dirname "$0")/../gvfs-1.62.0-ftp-charset.patch"

echo "==> 编译 gvfsd-ftp"
export PATH="$VENV/bin:$PATH"
meson setup build --prefix="$PREFIX" \
  -Dadmin=false -Dafc=false -Dcdda=false -Ddnssd=false -Dgoa=false \
  -Dgphoto2=false -Dhttp=false -Dmtp=false -Dnfs=false -Donedrive=false \
  -Dsftp=false -Dsmb=false -Dudisks2=false -Dwsdd=false -Dbluray=false \
  -Dgcr=false -Dgcrypt=false -Dgudev=false -Dlibusb=false \
  -Dman=false -Ddevel_utils=false -Dinstalled_tests=false -Dunit_tests=false
ninja -C build daemon/gvfsd-ftp

echo "==> 部署到 $LIBEXEC（用户级，无需 root）"
mkdir -p "$LIBEXEC" "$PREFIX/libexec/common" "$MOUNTS"
cp build/daemon/gvfsd-ftp "$LIBEXEC/"
cp build/daemon/libgvfsdaemon.so "$LIBEXEC/"
cp build/common/libgvfscommon.so "$PREFIX/libexec/common/"
cp /usr/share/gvfs/mounts/*.mount "$MOUNTS/"
for m in ftp ftps ftpis; do
  sed -i "s|^Exec=.*|Exec=$LIBEXEC/gvfsd-ftp|" "$MOUNTS/$m.mount"
done

echo "==> 让 gvfs-daemon 使用用户级 mount 定义并指定编码"
mkdir -p "$HOME/.config/systemd/user/gvfs-daemon.service.d"
cat > "$HOME/.config/systemd/user/gvfs-daemon.service.d/override.conf" <<CONF
[Service]
Environment=GVFS_MOUNTABLE_DIR=$MOUNTS
Environment=GVFS_FTP_CHARSET=${GVFS_FTP_CHARSET:-gbk}
CONF
systemctl --user daemon-reload
systemctl --user restart gvfs-daemon.service

echo "✓ 完成。Nautilus 里连 ftp://<服务器>/ 即可，编码由 GVFS_FTP_CHARSET 决定。"
