#!/usr/bin/env bash
# 从 windy664/gvfs（已含 charset 补丁的 fork）编译 gvfsd-ftp 并安装到用户目录。
# 不需要 root：二进制和 mount 定义都放在 ~/.local 下，靠 GVFS_MOUNTABLE_DIR 生效。
set -euo pipefail

SRC_DIR="${1:-$HOME/.cache/gvfs-src}"
PREFIX="$HOME/.local"
VENV="$HOME/.local/share/gvfs-build-venv"
MOUNTS="$PREFIX/share/gvfs/mounts"
LIBEXEC="$PREFIX/libexec/gvfs"
CHARSET="${GVFS_FTP_CHARSET:-gbk}"

echo "==> 拉取源码（含 charset 补丁的 fork）"
if [ ! -d "$SRC_DIR/.git" ]; then
  git clone --depth 1 https://github.com/windy664/gvfs.git "$SRC_DIR"
else
  git -C "$SRC_DIR" fetch --depth 1 origin master
  git -C "$SRC_DIR" reset --hard FETCH_HEAD
fi

echo "==> 准备构建工具"
if [ ! -x "$VENV/bin/meson" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install meson ninja
fi

echo "==> 编译 gvfsd-ftp"
export PATH="$VENV/bin:$PATH"
cd "$SRC_DIR"
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

echo "==> 配置 gvfs-daemon（编码 $CHARSET）"
mkdir -p "$HOME/.config/systemd/user/gvfs-daemon.service.d"
cat > "$HOME/.config/systemd/user/gvfs-daemon.service.d/override.conf" <<CONF
[Service]
Environment=GVFS_MOUNTABLE_DIR=$MOUNTS
Environment=GVFS_FTP_CHARSET=$CHARSET
CONF
systemctl --user daemon-reload
systemctl --user restart gvfs-daemon.service

echo "✓ 完成。Nautilus 里连 ftp://<服务器>/ 即可。"
