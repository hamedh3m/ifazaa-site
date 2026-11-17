#!/usr/bin/env bash
# تجهيز سيرفر فزعة (مرة وحدة، على Ubuntu 24.04):  sudo bash setup.sh <MIGRATE_KEY>
set -euo pipefail
MIGRATE_KEY="${1:?MIGRATE_KEY مطلوب}"
REPO="git@github.com:hamedh3m/fazaa-server.git"
BASE=/opt/fazaa
export DEBIAN_FRONTEND=noninteractive

echo "==> 1/6 تحديثات النظام"
apt-get update -q
apt-get -y -q -o Dpkg::Options::=--force-confold upgrade
apt-get install -y -q python3-venv python3-pip git caddy sqlite3 unattended-upgrades

echo "==> 2/6 مستخدم فزعة"
id fazaa >/dev/null 2>&1 || useradd --system --create-home --home-dir "$BASE" --shell /usr/sbin/nologin fazaa
install -d -o fazaa -g fazaa -m 700 "$BASE/data" "$BASE/.ssh"
[ -f "$BASE/.ssh/id_ed25519" ] || sudo -u fazaa ssh-keygen -q -t ed25519 -N "" -C fazaa-server -f "$BASE/.ssh/id_ed25519"
ssh-keyscan -t ed25519 github.com 2>/dev/null > "$BASE/.ssh/known_hosts"
chown fazaa:fazaa "$BASE/.ssh/known_hosts"

echo "==> 3/6 مفتاح السحب من GitHub (Deploy key)"
echo
echo "------------- انسخ السطر اللي تحت كامل -------------"
cat "$BASE/.ssh/id_ed25519.pub"
echo "----------------------------------------------------"
echo
until sudo -u fazaa git ls-remote "$REPO" >/dev/null 2>&1; do
  echo "⏳ أنتظر تضيف المفتاح في GitHub (Settings → Deploy keys)..."
  sleep 10
done
echo "✅ GitHub قبل المفتاح"

echo "==> 4/6 الكود"
[ -d "$BASE/app/.git" ] || sudo -u fazaa git clone -q "$REPO" "$BASE/app"
[ -d "$BASE/venv" ] || sudo -u fazaa python3 -m venv "$BASE/venv"
sudo -u fazaa "$BASE/venv/bin/pip" install -q --upgrade pip
sudo -u fazaa "$BASE/venv/bin/pip" install -q -r "$BASE/app/requirements.txt"
(cd "$BASE/app" && sudo -u fazaa "$BASE/venv/bin/python" -m pytest -q -p no:cacheprovider)

echo "==> 5/6 الإعدادات والتشغيل"
umask 027
printf 'FAZAA_DATA_DIR=%s/data\nMIGRATE_KEY=%s\n' "$BASE" "$MIGRATE_KEY" > /etc/fazaa.env
chown root:fazaa /etc/fazaa.env && chmod 640 /etc/fazaa.env
install -m 644 "$BASE/app/deploy/fazaa.service" /etc/systemd/system/fazaa.service
install -m 644 "$BASE/app/deploy/fazaa-update.service" /etc/systemd/system/fazaa-update.service
install -m 644 "$BASE/app/deploy/fazaa-update.timer" /etc/systemd/system/fazaa-update.timer
install -m 755 "$BASE/app/deploy/update.sh" /usr/local/bin/fazaa-update
install -m 644 "$BASE/app/deploy/Caddyfile" /etc/caddy/Caddyfile
systemctl daemon-reload
systemctl enable --now fazaa.service fazaa-update.timer
systemctl reload caddy || systemctl restart caddy

echo "==> 6/6 فحص"
sleep 3
curl -fsS http://127.0.0.1:8090/health && echo
echo "✅ خلصنا. السيرفر جاهز ينتظر بيانات فزعة من اللابتوب."
