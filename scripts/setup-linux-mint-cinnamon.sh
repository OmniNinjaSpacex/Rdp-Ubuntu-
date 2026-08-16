#!/usr/bin/env bash
set -Eeuo pipefail

RDP_USER="${RDP_USER:-cloudpc}"
TS_HOSTNAME="${TS_HOSTNAME:-gh-mint-${GITHUB_RUN_ID:-manual}}"

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

echo "==> Sistema base"
cat /etc/os-release | grep -E '^(NAME|VERSION)=' || true
nproc || true
free -h || true
df -h /

echo "==> Atualizando APT"
sudo apt-get update

echo "==> Instalando Cinnamon, XRDP e aplicativos"
COMMON_PACKAGES=(
  xrdp xorgxrdp xorg dbus-x11 x11-xserver-utils
  nemo gnome-terminal
  flatpak gnome-software gnome-software-plugin-flatpak
  policykit-1-gnome
  ca-certificates curl wget iptables xz-utils
  mesa-utils mesa-utils-extra
)

if apt-cache show cinnamon-desktop-environment >/dev/null 2>&1; then
  sudo apt-get install -y --no-install-recommends cinnamon-desktop-environment "${COMMON_PACKAGES[@]}"
else
  echo "cinnamon-desktop-environment não disponível; usando conjunto Cinnamon compatível."
  sudo apt-get install -y --no-install-recommends \
    cinnamon cinnamon-core cinnamon-session cinnamon-control-center \
    muffin cinnamon-settings-daemon "${COMMON_PACKAGES[@]}"
fi

CINNAMON_CMD=""
for candidate in cinnamon-session-cinnamon2d cinnamon-session; do
  if command -v "$candidate" >/dev/null 2>&1; then
    CINNAMON_CMD="$(command -v "$candidate")"
    break
  fi
done

if [[ -z "$CINNAMON_CMD" ]]; then
  echo "ERRO: nenhuma sessão Cinnamon foi encontrada." >&2
  ls -la /usr/share/xsessions || true
  exit 1
fi

echo "==> Sessão Cinnamon encontrada: $CINNAMON_CMD"

BROWSER_BIN=""
for candidate in google-chrome-stable google-chrome chromium chromium-browser; do
  if command -v "$candidate" >/dev/null 2>&1; then
    BROWSER_BIN="$(command -v "$candidate")"
    break
  fi
done

if [[ -z "$BROWSER_BIN" ]]; then
  echo "==> Navegador não encontrado; tentando instalar Google Chrome Stable"
  sudo apt-get install -y google-chrome-stable || true
  if command -v google-chrome-stable >/dev/null 2>&1; then
    BROWSER_BIN="$(command -v google-chrome-stable)"
  fi
fi

if [[ -z "$BROWSER_BIN" ]]; then
  echo "ERRO: Chrome/Chromium não encontrado." >&2
  exit 1
fi

echo "==> Navegador: $BROWSER_BIN"

echo "==> Instalando cursor estilo macOS"
CURSOR_TMP="$(mktemp -d)"
trap 'rm -rf "$CURSOR_TMP"' EXIT
CURSOR_ARCHIVE="$CURSOR_TMP/macOS.tar.xz"
curl -fL --retry 3 --retry-delay 2 \
  "https://github.com/ful1e5/apple_cursor/releases/download/v2.0.1/macOS.tar.xz" \
  -o "$CURSOR_ARCHIVE"
CURSOR_THEME="$(tar -tJf "$CURSOR_ARCHIVE" | sed -n '1{s#/.*##;p}')"
[[ -n "$CURSOR_THEME" ]] || CURSOR_THEME="macOS"
sudo tar -xJf "$CURSOR_ARCHIVE" -C /usr/share/icons
if [[ ! -d "/usr/share/icons/$CURSOR_THEME" ]]; then
  if [[ -d /usr/share/icons/macOS ]]; then
    CURSOR_THEME="macOS"
  else
    echo "ERRO: tema de cursor macOS não foi extraído corretamente." >&2
    exit 1
  fi
fi
sudo install -d /usr/share/icons/default
printf '[Icon Theme]\nInherits=%s\n' "$CURSOR_THEME" | sudo tee /usr/share/icons/default/index.theme >/dev/null
echo "==> Cursor instalado: $CURSOR_THEME"

echo "==> Criando usuário RDP: $RDP_USER"
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
  "$HOME_DIR/.local/share/applications" \
  "$HOME_DIR/.local/share" \
  "$HOME_DIR/.cache"
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
export XDG_CURRENT_DESKTOP="X-Cinnamon"
export XDG_SESSION_DESKTOP="cinnamon"
export DESKTOP_SESSION="cinnamon"
export LIBGL_ALWAYS_SOFTWARE=1
export XCURSOR_THEME="$CURSOR_THEME"
export XCURSOR_SIZE=32
unset DBUS_SESSION_BUS_ADDRESS
unset SESSION_MANAGER

if command -v cinnamon-session-cinnamon2d >/dev/null 2>&1; then
  exec dbus-run-session -- cinnamon-session-cinnamon2d
elif command -v cinnamon-session >/dev/null 2>&1; then
  exec dbus-run-session -- cinnamon-session --session cinnamon2d
else
  exec dbus-run-session -- cinnamon-session
fi
EOF_XSESSION

cat <<EOF_XSESSIONRC | sudo tee "$HOME_DIR/.xsessionrc" >/dev/null
export HOME="$HOME_DIR"
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export XDG_DATA_HOME="$HOME_DIR/.local/share"
export XDG_CACHE_HOME="$HOME_DIR/.cache"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
export XDG_CURRENT_DESKTOP="X-Cinnamon"
export XDG_SESSION_DESKTOP="cinnamon"
export DESKTOP_SESSION="cinnamon"
export LIBGL_ALWAYS_SOFTWARE=1
export XCURSOR_THEME="$CURSOR_THEME"
export XCURSOR_SIZE=32
EOF_XSESSIONRC

cat <<EOF_CURSOR | sudo tee "$HOME_DIR/.config/autostart/macos-cursor.desktop" >/dev/null
[Desktop Entry]
Type=Application
Name=macOS Cursor Theme
Exec=sh -c "gsettings set org.cinnamon.desktop.interface cursor-theme '$CURSOR_THEME' 2>/dev/null || true; gsettings set org.cinnamon.desktop.interface cursor-size 32 2>/dev/null || true; gsettings set org.gnome.desktop.interface cursor-theme '$CURSOR_THEME' 2>/dev/null || true; gsettings set org.gnome.desktop.interface cursor-size 32 2>/dev/null || true"
X-GNOME-Autostart-enabled=true
Terminal=false
EOF_CURSOR

cat <<EOF_BROWSER | sudo tee "$HOME_DIR/.local/share/applications/browser-cloudpc.desktop" >/dev/null
[Desktop Entry]
Type=Application
Name=Web Browser
Exec=$BROWSER_BIN --no-first-run %U
Icon=web-browser
Terminal=false
Categories=Network;WebBrowser;
EOF_BROWSER

cat <<'EOF_POLKIT' | sudo tee "$HOME_DIR/.config/autostart/polkit-agent.desktop" >/dev/null
[Desktop Entry]
Type=Application
Name=PolicyKit Authentication Agent
Exec=/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1
X-GNOME-Autostart-enabled=true
Terminal=false
EOF_POLKIT

sudo chown -R "$RDP_USER:$RDP_GROUP" \
  "$HOME_DIR/.config" "$HOME_DIR/.local" "$HOME_DIR/.cache" \
  "$HOME_DIR/.xsession" "$HOME_DIR/.xsessionrc"
sudo chmod 0755 "$HOME_DIR/.xsession"
sudo chmod 0644 "$HOME_DIR/.xsessionrc"

echo "==> Configurando Flatpak + Flathub"
sudo -u "$RDP_USER" env \
  HOME="$HOME_DIR" USER="$RDP_USER" LOGNAME="$RDP_USER" \
  XDG_CONFIG_HOME="$HOME_DIR/.config" \
  XDG_DATA_HOME="$HOME_DIR/.local/share" \
  XDG_CACHE_HOME="$HOME_DIR/.cache" \
  flatpak remote-add --user --if-not-exists \
  flathub https://flathub.org/repo/flathub.flatpakrepo

echo "==> Iniciando XRDP"
sudo adduser xrdp ssl-cert || true
sudo systemctl enable --now xrdp
sudo systemctl restart xrdp xrdp-sesman
sudo systemctl is-active --quiet xrdp
sudo systemctl is-active --quiet xrdp-sesman
sudo ss -ltn | grep ':3389'

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
  echo "ERRO: não foi possível obter o IPv4 Tailscale." >&2
  exit 1
fi

echo "==> Restringindo RDP à interface Tailscale"
sudo iptables -I INPUT 1 -i tailscale0 -p tcp --dport 3389 -j ACCEPT
sudo iptables -I INPUT 2 -p tcp --dport 3389 -j DROP
if command -v ip6tables >/dev/null 2>&1; then
  sudo ip6tables -I INPUT 1 -i tailscale0 -p tcp --dport 3389 -j ACCEPT || true
  sudo ip6tables -I INPUT 2 -p tcp --dport 3389 -j DROP || true
fi

cat > /tmp/mint-rdp-info <<EOF_INFO
TAILSCALE_IP=$TS_IP
RDP_USER=$RDP_USER
DESKTOP=Cinnamon
BROWSER_BIN=$BROWSER_BIN
CURSOR_THEME=$CURSOR_THEME
EOF_INFO

echo "==> Verificações finais"
id "$RDP_USER"
getent passwd "$RDP_USER"
ls -la /usr/share/xsessions || true
sudo systemctl --no-pager --full status xrdp | head -n 25 || true
free -h || true
df -h /

echo "Linux Mint/Cinnamon dev desktop pronto em $TS_IP; usuário $RDP_USER; cursor $CURSOR_THEME."
unset TAILSCALE_AUTHKEY RDP_PASSWORD
