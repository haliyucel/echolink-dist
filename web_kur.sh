#!/usr/bin/env bash
# ============================================================
#  EchoLink Linux - TEK SATIR KURULUM (ikili host modeli)
#  Kullanim:   curl -fsSL <KISA-LINK> | sudo bash
#  Yapar: mimariyi bulur -> dogru derlenmis ikiliyi INDIRIR ->
#         servisi kurar, acilista baslatir. Kaynak (.py) hic inmez.
#  Yapimci: TA6ABY - Hasan Ali YUCEL  (haliyucel@gmail.com)
# ------------------------------------------------------------
#  ONEMLI: Asagidaki TABAN_URL'yi ikililerin bulundugu adrese ayarla.
#  Ikililer soyle adlandirilmali:
#     echolink_panel-x86_64   echolink_panel-aarch64
#     echolink_panel-armv7    echolink_panel-armv6
# ============================================================
set -e

TABAN_URL="https://github.com/haliyucel/echolink-dist/releases/latest/download"

if [ "$(id -u)" -ne 0 ]; then
  echo "[HATA] Yonetici gerekli.  Soyle calistir:"
  echo "   curl -fsSL <link> | sudo bash"
  exit 1
fi

# --- mimari tespiti ---
M="$(uname -m)"
case "$M" in
  x86_64|amd64)      A="x86_64" ;;
  aarch64|arm64)     A="aarch64" ;;
  armv7l|armv7)      A="armv7" ;;
  armv6l|armv6)      A="armv6" ;;
  *) echo "[HATA] Desteklenmeyen mimari: $M"; exit 1 ;;
esac
echo "[i] Mimari: $M -> $A"

DIZIN="/opt/echolink"
mkdir -p "$DIZIN/kayitlar"

# --- calisma-zamani araclari (MP3 kaydi + ses cikisi) - COK DAGITIMLI ---
# lame  = MP3 kodlayici (kayitlar kucuk olsun)
# alsa-utils = 'aplay' (ses cikisi + cihaz listesi)
# curl  = indirici
echo "[i] Gerekli araclar kuruluyor (lame, alsa-utils, curl)..."
if command -v apt-get >/dev/null 2>&1; then          # Debian/Ubuntu/RaspberryPiOS
  apt-get update -y || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y lame alsa-utils curl || true
elif command -v dnf >/dev/null 2>&1; then            # Fedora/RHEL
  dnf install -y lame alsa-utils curl || true
elif command -v pacman >/dev/null 2>&1; then         # Arch/Manjaro
  pacman -Sy --noconfirm lame alsa-utils curl || true
elif command -v zypper >/dev/null 2>&1; then         # openSUSE
  zypper --non-interactive install lame alsa-utils curl || true
elif command -v apk >/dev/null 2>&1; then            # Alpine
  apk add --no-cache lame alsa-utils curl || true
else
  echo "[UYARI] Paket yoneticisi taninmadi. 'lame', 'alsa-utils', 'curl'"
  echo "        paketlerini elle kurman gerekebilir (MP3 kaydi/ses cikisi icin)."
fi

# --- USB seri (PTT) izinleri: kullaniciyi dialout/uucp grubuna ekle ---
# Linux'ta USB-seri surucusu (cp210x/ftdi_sio/ch341/pl2303) cekirdekte gomulu,
# otomatik yuklenir. Asil sorun cogu zaman IZINDIR: kullanici seri porta
# erisemez. Onu dialout (Debian) ya da uucp (Arch/Fedora) grubuna ekleriz.
KULL="${SUDO_USER:-}"
if [ -n "$KULL" ] && [ "$KULL" != "root" ]; then
  for grup in dialout uucp; do
    if getent group "$grup" >/dev/null 2>&1; then
      usermod -aG "$grup" "$KULL" 2>/dev/null \
        && echo "[i] '$KULL' kullanicisi '$grup' grubuna eklendi (seri PTT izni)." \
        && echo "    (Not: bu iznin gecerli olmasi icin bir kez cikis/giris ya da yeniden baslatma gerekebilir.)"
    fi
  done
fi

# --- ikiliyi indir ---
URL="$TABAN_URL/echolink_panel-$A"
echo "[i] Ikili indiriliyor: $URL"
if ! curl -fsSL "$URL" -o "$DIZIN/echolink_panel"; then
  echo ""
  echo "############ [HATA] IKILI INDIRILEMEDI ############"
  echo " Adres: $URL"
  echo " Yapman gerekenler:"
  echo "  1) Internet baglantini kontrol et."
  echo "  2) Bu adresi tarayicida ac; dosya iniyor mu bak:"
  echo "     $URL"
  echo "  3) O surumde '$A' ikilisi var mi kontrol et (echolink-dist -> Releases)."
  echo "###################################################"
  exit 1
fi
chmod +x "$DIZIN/echolink_panel"

# --- systemd servisi ---
cat >/etc/systemd/system/echolink.service <<EOF
[Unit]
Description=EchoLink Linux Panel (RoIP - sadece EchoLink)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$DIZIN
ExecStart=$DIZIN/echolink_panel
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable echolink >/dev/null 2>&1 || true
systemctl restart echolink

sleep 3
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

# --- servis gercekten calisiyor mu? (saglik kontrolu) ---
if systemctl is-active --quiet echolink; then
  echo "=================================================="
  echo " KURULUM TAMAM (korumali ikili, kaynak inmedi)."
  echo " Panel:  http://${IP:-<makine-ip>}:8080"
  echo " Durum:  systemctl status echolink"
  echo " Kaldir: sudo systemctl disable --now echolink; sudo rm -rf $DIZIN"
  echo "=================================================="
else
  echo ""
  echo "############ [UYARI] SERVIS BASLAMADI ############"
  echo " Kurulum tamamlandi ama panel su an calismiyor."
  echo " En sik sebep: 8080 portu baska bir programca kullaniliyor,"
  echo " ya da ikili izin/uyum sorunu. Sunlari SIRAYLA dene:"
  echo ""
  echo "  # 1) Hatayi gor:"
  echo "     sudo journalctl -u echolink -n 30 --no-pager"
  echo ""
  echo "  # 2) 8080 portu doluysa bosalt ve yeniden baslat:"
  echo "     sudo fuser -k 8080/tcp"
  echo "     sudo systemctl restart echolink"
  echo ""
  echo "  # 3) Baska port kullan (or. 8090):"
  echo "     echo '{\"panel_port\": 8090}' | sudo tee $DIZIN/ayarlar.json"
  echo "     sudo systemctl restart echolink"
  echo "     # sonra:  http://${IP:-<makine-ip>}:8090"
  echo ""
  echo "  # 4) Izin sorunu olursa:"
  echo "     sudo chmod +x $DIZIN/echolink_panel"
  echo "     sudo systemctl restart echolink"
  echo ""
  echo "  # 5) Elle deneyip ham hatayi gormek istersen:"
  echo "     sudo $DIZIN/echolink_panel"
  echo "##################################################"
fi
