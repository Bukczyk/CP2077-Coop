#!/usr/bin/env bash
set -euo pipefail
if [[ $(id -u) != 0 ]]; then echo "Run with sudo" >&2; exit 1; fi
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
binary="${1:?Usage: sudo bash install.sh /path/CP2077SessionServer [bind IPv4] [access.key]}"
bind_ip="${2:-127.0.0.1}"
if [[ ! "$bind_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "Invalid IPv4" >&2; exit 1; fi
if ! id cp2077-coop >/dev/null 2>&1; then useradd --system --no-create-home --shell /usr/sbin/nologin cp2077-coop; fi
install -d -m 0750 -o root -g cp2077-coop /etc/cp2077-coop
if [[ ! -f "$binary" || ! -x "$binary" ]]; then echo "Missing executable server binary" >&2; exit 1; fi
install -m 0755 "$binary" /usr/local/bin/CP2077SessionServer.new
mv -f /usr/local/bin/CP2077SessionServer.new /usr/local/bin/CP2077SessionServer
if [[ -n "${3:-}" ]]; then
  install -m 0640 -o root -g cp2077-coop "$3" /etc/cp2077-coop/access.key
elif [[ ! -f /etc/cp2077-coop/access.key ]]; then
  (umask 027; od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > /etc/cp2077-coop/access.key)
  chown root:cp2077-coop /etc/cp2077-coop/access.key
fi
if [[ -f /etc/cp2077-coop/server.ini ]]; then
  cp -p /etc/cp2077-coop/server.ini "/etc/cp2077-coop/server.ini.backup.$(date +%s)"
fi
sed "s/^bind=.*/bind=$bind_ip/" "$source_dir/server.ini" > /etc/cp2077-coop/server.ini
chown root:cp2077-coop /etc/cp2077-coop/server.ini
chmod 0640 /etc/cp2077-coop/server.ini
install -m 0644 "$source_dir/cp2077-coop.service" /etc/systemd/system/cp2077-coop.service
systemctl daemon-reload
systemctl enable --now cp2077-coop
systemctl restart cp2077-coop
systemctl --no-pager status cp2077-coop
