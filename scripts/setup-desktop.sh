#!/usr/bin/env bash
set -Eeuo pipefail

RDP_USER="${RDP_USER:-cloudpc}"
TS_HOSTNAME="${TS_HOSTNAME:-gh-xfce-${GITHUB_RUN_ID:-manual}}"

: "${TAILSCALE_AUTHKEY:?TAILSCALE_AUTHKEY não definido}"
: "${RDP_PASSWORD:?RDP_PASSWORD não definido}"

if [[ "$EUID" -eq 0 ]]; then
  echo "ERRO: execute este script como o usuário normal do runner; ele usa sudo internamente." >&2
  exit 1
fi

if [[ ${#RDP_PASSWORD} -lt 12 ]]; then
  echo "ERRO: RDP_PASSWORD deve ter pelo menos 12 caracteres." >&2
  exit 1
fi

if [[ "$RDP_PASSWORD" == *:* || "$RDP_PASSWORD" == *$'\n'* || "$RDP_PASSWORD" == *$'\r'* ]]; then
  echo "ERRO: RDP_PASSWORD não pode conter ':' nem quebras de linha." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "==> Espaço em disco antes da instalação"
df -h /

echo "==> Instalando Xfce, XRDP e aplicativos"
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  xfce4 xfce4-goodies xorg dbus-x11 x11-xserver-utils \
  xrdp xorgxrdp \
  thunar xfce4-terminal mousepad plank \
  papirus-icon-theme arc-theme \
  gnome-software gnome-software-plugin-flatpak flatpak \
  policykit-1-gnome \
  ca-certificates curl wget iptables

CHROMIUM_BIN=""
for candidate in chromium chromium-browser google-chrome google-chrome-stable; do
  if command -v "$candidate" >/dev/null 2>&1; then
    CHROMIUM_BIN="$(command -v "$candidate")"
    break
  fi
done

if [[ -z "$CHROMIUM_BIN" ]]; then
  echo "ERRO: Chromium/Chrome não foi encontrado na imagem atual do runner." >&2
  exit 1
fi

echo "==> Criando usuário RDP: ${RDP_USER}"
if ! id "$RDP_USER" >/dev/null 2>&1; then
  sudo useradd --create-home --shell /bin/bash "$RDP_USER"
fi

printf '%s:%s\n' "$RDP_USER" "$RDP_PASSWORD" | sudo chpasswd
sudo usermod -aG sudo,ssl-cert "$RDP_USER"

HOME_DIR="$(getent passwd "$RDP_USER" | cut -d: -f6)"
RDP_GROUP="$(id -gn "$RDP_USER")"

sudo install -d -m 0755 -o "$RDP_USER" -g "$RDP_GROUP" \
  "$HOME_DIR/.config/autostart" \
  "$HOME_DIR/.local/share/applications" \
  "$HOME_DIR/.icons"

printf '%s\n' 'exec xfce4-session' | sudo tee "$HOME_DIR/.xsession" >/dev/null
sudo chown "$RDP_USER:$RDP_GROUP" "$HOME_DIR/.xsession"
sudo chmod 0644 "$HOME_DIR/.xsession"

echo "==> Instalando cursor GoogleDot-Black"
CURSOR_TMP="$(mktemp -d)"
trap 'rm -rf "$CURSOR_TMP"' EXIT

curl -fL --retry 3 --retry-delay 2 \
  "https://github.com/ful1e5/Google_Cursor/releases/latest/download/GoogleDot-Black.tar.gz" \
  -o "$CURSOR_TMP/GoogleDot-Black.tar.gz"

sudo tar -xzf "$CURSOR_TMP/GoogleDot-Black.tar.gz" -C /usr/share/icons

if [[ ! -d /usr/share/icons/GoogleDot-Black ]]; then
  echo "ERRO: o tema GoogleDot-Black não foi extraído como esperado." >&2
  exit 1
fi

sudo -H -u "$RDP_USER" dbus-run-session -- bash <<'XFCONF'
set -e

xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s Arc \
  || xfconf-query -c xsettings -p /Net/ThemeName -s Arc

xfconf-query -c xsettings -p /Net/IconThemeName -n -t string -s Papirus \
  || xfconf-query -c xsettings -p /Net/IconThemeName -s Papirus

xfconf-query -c xsettings -p /Gtk/CursorThemeName -n -t string -s GoogleDot-Black \
  || xfconf-query -c xsettings -p /Gtk/CursorThemeName -s GoogleDot-Black

xfconf-query -c xsettings -p /Gtk/CursorThemeSize -n -t int -s 32 \
  || xfconf-query -c xsettings -p /Gtk/CursorThemeSize -s 32
XFCONF

cat <<'EOF_PLANK' | sudo tee "$HOME_DIR/.config/autostart/plank.desktop" >/dev/null
[Desktop Entry]
Type=Application
Name=Plank
Exec=plank
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
Terminal=false
EOF_PLANK

cat <<'EOF_POLKIT' | sudo tee "$HOME_DIR/.config/autostart/polkit-gnome-authentication-agent-1.desktop" >/dev/null
[Desktop Entry]
Type=Application
Name=PolicyKit Authentication Agent
Exec=/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
Terminal=false
EOF_POLKIT

cat <<EOF_CHROMIUM | sudo tee "$HOME_DIR/.local/share/applications/chromium-cloudpc.desktop" >/dev/null
[Desktop Entry]
Type=Application
Name=Chromium
Exec=$CHROMIUM_BIN --no-first-run %U
Icon=chromium
Terminal=false
Categories=Network;WebBrowser;
EOF_CHROMIUM

sudo chown -R "$RDP_USER:$RDP_GROUP" \
  "$HOME_DIR/.config" \
  "$HOME_DIR/.local" \
  "$HOME_DIR/.icons"

echo "==> Habilitando Flatpak/Flathub"
sudo -H -u "$RDP_USER" flatpak remote-add --user --if-not-exists \
  flathub https://flathub.org/repo/flathub.flatpakrepo

echo "==> Iniciando XRDP"
sudo systemctl enable --now xrdp
sudo systemctl restart xrdp
sudo systemctl is-active --quiet xrdp

echo "==> Instalando e conectando Tailscale"
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

sudo systemctl enable --now tailscaled
sudo tailscale up \
  --auth-key="$TAILSCALE_AUTHKEY" \
  --hostname="$TS_HOSTNAME" \
  --accept-dns=false

TS_IP="$(sudo tailscale ip -4 | head -n1)"

if [[ ! "$TS_IP" =~ ^100\. ]]; then
  echo "ERRO: não foi possível obter um IPv4 Tailscale (100.x.x.x)." >&2
  echo "Valor recebido: '$TS_IP'" >&2
  exit 1
fi

echo "==> Restringindo RDP à interface Tailscale"
sudo iptables -I INPUT 1 -i tailscale0 -p tcp --dport 3389 -j ACCEPT
sudo iptables -I INPUT 2 -p tcp --dport 3389 -j DROP

if command -v ip6tables >/dev/null 2>&1; then
  sudo ip6tables -I INPUT 1 -i tailscale0 -p tcp --dport 3389 -j ACCEPT || true
  sudo ip6tables -I INPUT 2 -p tcp --dport 3389 -j DROP || true
fi

sudo ss -ltn | grep -q ':3389' || {
  echo "ERRO: XRDP não está escutando em TCP/3389." >&2
  exit 1
}

cat > /tmp/cloudpc-info <<EOF_INFO
TAILSCALE_IP=$TS_IP
RDP_USER=$RDP_USER
TAILSCALE_HOSTNAME=$TS_HOSTNAME
EOF_INFO

echo "==> Limpando cache APT para preservar o SSD temporário"
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

echo "==> Espaço em disco após a instalação"
df -h /

echo "Ubuntu Desktop pronto em $TS_IP; usuário $RDP_USER."
unset TAILSCALE_AUTHKEY RDP_PASSWORD
