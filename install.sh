#!/usr/bin/env bash
# Install the Resolve repair script and wire it to a pacman hook, so the fixes
# are re-applied automatically every time davinci-resolve-studio is upgraded
# or reinstalled. Run with:
#
#   sudo bash install.sh
#
# Installs:
#   /usr/local/bin/omarchy-resolve-fix
#   /etc/pacman.d/hooks/99-davinci-resolve-fix.hook
#
# To uninstall, delete those two files. Nothing else is touched.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "error: run this with sudo -- sudo bash $0" >&2
  exit 1
fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
target_user=${SUDO_USER:-}

if [[ -z $target_user || $target_user == root ]]; then
  echo "error: could not determine the desktop user from SUDO_USER." >&2
  echo "       run as: sudo bash $0   (not from a root shell)" >&2
  exit 2
fi

echo "Installing for user: $target_user"

install -Dm755 "$here/bin/omarchy-resolve-fix" /usr/local/bin/omarchy-resolve-fix
echo "  installed /usr/local/bin/omarchy-resolve-fix"

install -d /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/99-davinci-resolve-fix.hook <<HOOK
# Re-apply the DaVinci Resolve fixes after any package operation that would
# undo them. The AUR package does not create /opt/resolve/{Extras,Fairlight}
# and does not link the panel API libraries into /usr/lib64, so both are lost
# on every upgrade. See: https://github.com/basecamp/omarchy/issues/437

[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = davinci-resolve
Target = davinci-resolve-studio

[Action]
Description = Re-applying DaVinci Resolve fixes (content dirs, panel API libs)...
When = PostTransaction
Exec = /usr/local/bin/omarchy-resolve-fix --user $target_user --quiet
HOOK
echo "  installed /etc/pacman.d/hooks/99-davinci-resolve-fix.hook"

echo
echo "Applying fixes now..."
/usr/local/bin/omarchy-resolve-fix --user "$target_user"
