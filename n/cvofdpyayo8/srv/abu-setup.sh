#!/usr/bin/env bash
# تجهيز أبو محمد على السيرفر (مرة وحدة، Ubuntu 24.04):  sudo bash cloud-setup.sh <ABU_MIGRATE_KEY>
set -euo pipefail
KEY="${1:?ABU_MIGRATE_KEY مطلوب}"
REPO="git@github.com:hamedh3m/abu-mohammed.git"
BASE=/opt/abu
export DEBIAN_FRONTEND=noninteractive

echo "==> 1/7 أدوات النظام وذاكرة إضافية"
apt-get update -q
apt-get install -y -q python3-venv python3-pip git sqlite3 ffmpeg curl
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "==> 2/7 مستخدم أبو محمد"
id abu >/dev/null 2>&1 || useradd --system --create-home --home-dir "$BASE" --shell /usr/sbin/nologin abu
install -d -o abu -g abu -m 700 "$BASE/data" "$BASE/.ssh"
[ -f "$BASE/.ssh/id_ed25519" ] || sudo -u abu ssh-keygen -q -t ed25519 -N "" -C abu-server -f "$BASE/.ssh/id_ed25519"
ssh-keyscan -t ed25519 github.com 2>/dev/null > "$BASE/.ssh/known_hosts"
chown abu:abu "$BASE/.ssh/known_hosts"

echo "==> 3/7 مفتاح السحب من GitHub (Deploy key لمستودع abu-mohammed)"
echo
echo "------------- انسخ السطر اللي تحت كامل -------------"
cat "$BASE/.ssh/id_ed25519.pub"
echo "----------------------------------------------------"
echo
until sudo -u abu git ls-remote "$REPO" >/dev/null 2>&1; do
  echo "⏳ أنتظر تضيف المفتاح في GitHub (abu-mohammed → Settings → Deploy keys)..."
  sleep 10
done
echo "✅ GitHub قبل المفتاح"

echo "==> 4/7 الكود والمكتبات (المتصفح ياخذ دقايق)"
[ -d "$BASE/app/.git" ] || sudo -u abu git clone -q "$REPO" "$BASE/app"
[ -d "$BASE/venv" ] || sudo -u abu python3 -m venv "$BASE/venv"
sudo -u abu "$BASE/venv/bin/pip" install -q --upgrade pip
sudo -u abu "$BASE/venv/bin/pip" install -q -r "$BASE/app/requirements.txt"
PLAYWRIGHT_BROWSERS_PATH="$BASE/pw" "$BASE/venv/bin/python" -m playwright install-deps chromium >/dev/null
sudo -u abu env PLAYWRIGHT_BROWSERS_PATH="$BASE/pw" "$BASE/venv/bin/python" -m playwright install chromium >/dev/null
ln -sfn "$BASE/data/.env" "$BASE/app/.env"
(cd "$BASE/app" && sudo -u abu "$BASE/venv/bin/python" -m pytest -q -p no:cacheprovider)

echo "==> 5/7 الإعدادات والتشغيل"
umask 027
printf 'DATA_DIR=%s/data\nABU_MIGRATE_KEY=%s\nPLAYWRIGHT_BROWSERS_PATH=%s/pw\nPYTHONUTF8=1\nWHISPER_MODEL=\n' "$BASE" "$KEY" "$BASE" > /etc/abu.env
chown root:abu /etc/abu.env && chmod 640 /etc/abu.env
install -m 644 "$BASE/app/deploy/abu.service" /etc/systemd/system/abu.service
install -m 644 "$BASE/app/deploy/abu-update.service" /etc/systemd/system/abu-update.service
install -m 644 "$BASE/app/deploy/abu-update.timer" /etc/systemd/system/abu-update.timer
install -m 755 "$BASE/app/deploy/update.sh" /usr/local/bin/abu-update
systemctl daemon-reload
systemctl enable --now abu.service abu-update.timer

echo "==> 6/7 Tailscale (شبكتك الخاصة)"
command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
if ! tailscale status >/dev/null 2>&1; then
  echo "افتح الرابط اللي بيطلع تحت ووافق عشان السيرفر يدخل شبكتك:"
  tailscale up --ssh=false
fi
tailscale serve --bg 8080 >/dev/null
echo "✅ Tailscale: $(tailscale status --self --peers=false | awk 'NR==1{print $2}')"

echo "==> 7/7 فحص"
sleep 3
curl -fsS http://127.0.0.1:8080/health && echo
echo "✅ خلصنا. أبو محمد جاهز على السيرفر وينتظر بياناته من اللابتوب."
