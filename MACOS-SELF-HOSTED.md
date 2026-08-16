# macOS self-hosted + Tailscale + Screen Sharing

Esta versão usa um **Mac real** como computador remoto. O GitHub Actions apenas verifica se o Mac está online e pronto; ele não cria o hardware nem uma VM macOS.

## O que você precisa

- Um Mac ou Mac mini ligado, com macOS suportado pelo GitHub Actions self-hosted runner.
- Uma conta de usuário no Mac.
- Tailscale instalado e conectado à mesma tailnet do celular.
- Screen Sharing do macOS ativado.
- O GitHub self-hosted runner registrado neste repositório.

## 1. Instale e conecte o Tailscale no Mac

Use a versão Standalone oficial do Tailscale para macOS. Abra o aplicativo, aprove as permissões solicitadas pelo macOS e conecte o Mac à mesma tailnet usada no celular.

O workflow procura primeiro o comando `tailscale` e, se não estiver instalado no PATH, usa diretamente:

`/Applications/Tailscale.app/Contents/MacOS/Tailscale`

## 2. Ative a tela remota no macOS

No Mac:

1. Abra **Ajustes do Sistema**.
2. Vá em **Geral > Compartilhamento**.
3. Se **Gerenciamento Remoto** estiver ativo, desative-o.
4. Ative **Compartilhamento de Tela**.
5. Abra o botão de informações do Compartilhamento de Tela.
6. Em **Permitir acesso para**, escolha somente o usuário que você deseja usar.
7. Para conectar a partir de um cliente VNC não-Apple, ative **Visualizadores VNC controlam a tela com a senha** e crie uma senha VNC exclusiva.

**Não reutilize a senha da conta local do Mac como senha VNC.**

O serviço normalmente usa TCP **5900**.

## 3. Registre o Mac como runner self-hosted

Neste repositório, abra:

**Settings > Actions > Runners > New self-hosted runner > macOS**

Escolha a arquitetura correta do Mac e execute **no Terminal do próprio Mac** exatamente os comandos que o GitHub mostrar. O token de registro é temporário, então use o comando gerado na hora.

Depois que o runner estiver configurado, você pode instalar o runner como serviço seguindo as instruções oficiais mostradas pelo GitHub para macOS. O objetivo é que o runner volte a ficar online automaticamente quando o Mac iniciar.

O runner recebe automaticamente os labels `self-hosted` e `macOS`, que são os labels usados pelo workflow deste repositório.

## 4. Rode a verificação

Abra:

**Actions > macOS Self-Hosted - Tailscale Screen Sharing > Run workflow**

Se tudo estiver pronto, o Summary vai mostrar algo semelhante a:

```text
macOS: 26.x
Arquitetura: arm64
IP Tailscale: 100.x.x.x
Porta: 5900
```

## 5. Conecte pelo celular

1. Ative o Tailscale no celular e conecte à mesma tailnet.
2. Abra um cliente VNC compatível no Android.
3. Use o endereço mostrado pelo workflow:

```text
100.x.x.x:5900
```

4. Use a **senha VNC** definida nas opções de Compartilhamento de Tela do Mac.

O Windows App/RDP não é o protocolo usado aqui. O compartilhamento de tela do macOS é compatível com VNC.

## Como esta versão funciona

```text
Celular Android
      │
      │ Tailscale (rede privada)
      ▼
100.x.x.x
      │
      │ TCP 5900 / VNC
      ▼
Mac real
├── macOS
├── Finder
├── Dock
├── Safari
├── Terminal
├── Apps instalados no Mac
├── Screen Sharing
└── GitHub self-hosted runner
```

A tela e os arquivos ficam no próprio Mac. Encerrar um workflow do GitHub **não apaga o Mac e não encerra o ambiente gráfico**.

## Limitações importantes

- O Mac precisa existir fisicamente e permanecer ligado.
- O GitHub self-hosted runner não fornece RAM, CPU ou armazenamento: esses recursos são os do próprio Mac.
- Em macOS moderno, o Screen Sharing deve ser habilitado nas configurações do Mac; o workflow não tenta contornar essa proteção do sistema.
- O Tailscale para macOS pode pedir aprovação de extensão de sistema/VPN na primeira instalação.
- Para acesso após reinicializações sem ninguém logado, o comportamento depende da variante do Tailscale e da configuração do próprio Mac.
