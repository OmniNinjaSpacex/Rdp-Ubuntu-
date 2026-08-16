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

echo "==> Sistema"
grep -E '^(NAME|VERSION)=' /etc/os-release || true

echo "==> Espaço em disco antes da instalação"
df -h /

echo "==> Instalando Xfce, XRDP e aplicativos"
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  xfce4 xfce4-goodies xorg dbus-x11 dbus-user-session x11-xserver-utils \
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

echo "==> Navegador encontrado: $CHROMIUM_BIN"

echo "==> Criando usuário RDP: ${RDP_USER}"
if ! id "$RDP_USER" >/dev/null 2>&1; then
  sudo useradd --create-home --shell /bin/bash "$RDP_USER"
fi

printf '%s:%s\n' "$RDP_USER" "$RDP_PASSWORD" | sudo chpasswd
sudo usermod -aG sudo,ssl-cert "$RDP_USER"

HOME_DIR="$(getent passwd "$RDP_USER" | cut -d: -f6)"
RDP_GROUP="$(id -gn "$RDP_USER")"
RUNTIME_DIR="/tmp/xdg-runtime-$RDP_USER"

sudo install -d -m 0755 -o "$RDP_USER" -g "$RDP_GROUP" \
  "$HOME_DIR/.config/autostart" \
  "$HOME_DIR/.config/xfce4/xfconf/xfce-perchannel-xml" \
  "$HOME_DIR/.local/share/applications" \
  "$HOME_DIR/.local/share" \
  "$HOME_DIR/.cache" \
  "$HOME_DIR/.icons"

# GitHub-hosted runners já possuem um usuário runner e variáveis XDG próprias.
# Uma sessão XRDP do cloudpc não deve herdá-las. O launcher abaixo cria um
# ambiente XDG/DBus limpo e próprio antes de iniciar o xfce4-session.
sudo install -d -m 0700 -o "$RDP_USER" -g "$RDP_GROUP" "$RUNTIME_DIR"

cat <<EOF_XSESSION | sudo tee "$HOME_DIR/.xsession" >/dev/null
#!/usr/bin/env bash
export HOME="$HOME_DIR"
export USER="$RDP_USER"
export LOGNAME="$RDP_USER"
export SHELL=/bin/bash
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export XDG_DATA_HOME="$HOME_DIR/.local/share"
export XDG_CACHE_HOME="$HOME_DIR/.cache"
export XDG_CONFIG_DIRS="/etc/xdg"
export XDG_DATA_DIRS="/usr/local/share:/usr/share"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
unset DBUS_SESSION_BUS_ADDRESS
unset SESSION_MANAGER
exec dbus-run-session -- xfce4-session
EOF_XSESSION

sudo chown "$RDP_USER:$RDP_GROUP" "$HOME_DIR/.xsession"
sudo chmod 0755 "$HOME_DIR/.xsession"

# Também disponibilizamos as variáveis cedo para o /etc/X11/Xsession.
cat <<EOF_XSESSIONRC | sudo tee "$HOME_DIR/.xsessionrc" >/dev/null
export HOME="$HOME_DIR"
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export XDG_DATA_HOME="$HOME_DIR/.local/share"
export XDG_CACHE_HOME="$HOME_DIR/.cache"
export XDG_CONFIG_DIRS="/etc/xdg"
export XDG_DATA_DIRS="/usr/local/share:/usr/share"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
unset DBUS_SESSION_BUS_ADDRESS
unset SESSION_MANAGER
EOF_XSESSIONRC
sudo chown "$RDP_USER:$RDP_GROUP" "$HOME_DIR/.xsessionrc"
sudo chmod 0644 "$HOME_DIR/.xsessionrc"

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

echo "==> Configurando tema ChromeOS-like do Xfce"
cat <<'EOF_XSETTINGS' | sudo tee "$HOME_DIR/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" >/dev/null
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Arc"/>
    <property name="IconThemeName" type="string" value="Papirus"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="CursorThemeName" type="string" value="GoogleDot-Black"/>
    <property name="CursorThemeSize" type="int" value="32"/>
  </property>
</channel>
EOF_XSETTINGS

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
Name=Chromium / Chrome
Exec=$CHROMIUM_BIN --no-first-run %U
Icon=chromium
Terminal=false
Categories=Network;WebBrowser;
EOF_CHROMIUM

sudo chown -R "$RDP_USER:$RDP_GROUP" \
  "$HOME_DIR/.config" \
  "$HOME_DIR/.local" \
  "$HOME_DIR/.cache" \
  "$HOME_DIR/.icons"

echo "==> Habilitando Flatpak/Flathub"
sudo -u "$RDP_USER" env \
  HOME="$HOME_DIR" \
  USER="$RDP_USER" \
  LOGNAME="$RDP_USER" \
  XDG_CONFIG_HOME="$HOME_DIR/.config" \
  XDG_DATA_HOME="$HOME_DIR/.local/share" \
  XDG_CACHE_HOME="$HOME_DIR/.cache" \
  XDG_CONFIG_DIRS="/etc/xdg" \
  XDG_DATA_DIRS="/usr/local/share:/usr/share" \
  XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  flatpak remote-add --user --if-not-exists \
  flathub https://flathub.org/repo/flathub.flatpakrepo

echo "==> Verificando launcher da sessão Xfce"
sudo -u "$RDP_USER" env \
  HOME="$HOME_DIR" \
  XDG_CONFIG_HOME="$HOME_DIR/.config" \
  XDG_CONFIG_DIRS="/etc/xdg" \
  XDG_RUNTIME_DIR="$RUNTIME_DIR" \
  bash -n "$HOME_DIR/.xsession"

test -x /usr/bin/xfce4-session
test -x /usr/bin/dbus-run-session
test -d /etc/xdg

echo "==> Iniciando XRDP"
sudo systemctl enable --now xrdp
sudo systemctl restart xrdp
sudo systemctl is-active --quiet xrdp
sudo ss -ltn | grep ':3389' || true

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
  sudo systemctl status xrdp --no-pager || true
  exit 1
}

cat > /tmp/cloudpc-info <<EOF_INFO
TAILSCALE_IP=$TS_IP
RDP_USER=$RDP_USER
TAILSCALE_HOSTNAME=$TS_HOSTNAME
EOF_INFO

echo "==> Limpando cache APT"
sudo apt-get clean

echo "==> Espaço em disco após a instalação"
df -h /

echo "Ubuntu Desktop pronto em $TS_IP; usuário $RDP_USER."
unset TAILSCALE_AUTHKEY RDP_PASSWORD
