#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERRO: este workflow precisa rodar em um Mac self-hosted." >&2
  exit 1
fi

MACOS_VERSION="$(sw_vers -productVersion)"
MACOS_ARCH="$(uname -m)"

echo "==> macOS $MACOS_VERSION ($MACOS_ARCH)"

TS_CMD=""
if command -v tailscale >/dev/null 2>&1; then
  TS_CMD="$(command -v tailscale)"
elif [[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]]; then
  TS_CMD="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
else
  echo "ERRO: Tailscale não foi encontrado neste Mac." >&2
  echo "Instale o Tailscale para macOS e conecte este Mac à sua tailnet antes de rodar o workflow." >&2
  exit 1
fi

export TAILSCALE_BE_CLI=1
TAILSCALE_IP="$($TS_CMD ip -4 2>/dev/null | head -n 1 || true)"

if [[ ! "$TAILSCALE_IP" =~ ^100\. ]]; then
  echo "ERRO: o Mac não está conectado ao Tailscale ou não recebeu um IPv4 100.x.x.x." >&2
  echo "Abra o Tailscale no Mac, conecte à tailnet e rode novamente." >&2
  exit 1
fi

echo "==> Tailscale conectado: $TAILSCALE_IP"

if ! nc -z 127.0.0.1 5900 >/dev/null 2>&1; then
  echo "ERRO: o Screen Sharing/VNC não está escutando na porta TCP 5900." >&2
  echo "No Mac: Ajustes do Sistema > Geral > Compartilhamento > desative Gerenciamento Remoto > ative Compartilhamento de Tela." >&2
  echo "Depois abra as opções do Compartilhamento de Tela e permita o usuário desejado." >&2
  exit 1
fi

echo "==> Screen Sharing ativo em TCP/5900"

cat > /tmp/macos-remote-info <<EOF
MACOS_VERSION='$MACOS_VERSION'
MACOS_ARCH='$MACOS_ARCH'
TAILSCALE_IP='$TAILSCALE_IP'
VNC_PORT='5900'
EOF

echo
printf 'Mac remoto pronto: %s:5900\n' "$TAILSCALE_IP"
