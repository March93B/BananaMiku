# Minha build do BananaOS (RG DS Plus)

Eu mantenho uma versão própria do BananaOS: **sempre faço o merge do projeto oficial e compilo eu mesmo**. A
atualização pelo próprio sistema (Settings › System › Updates) busca as releases **do meu fork** (March93B/BananaMiku),
não as oficiais: eu publico uma release e o console a encontra em "Verificar atualizações".

## O que esta build tem a mais

| Mudança | Arquivos | Por quê |
|---|---|---|
| Chave `"sheetMix"` no tema (0 a 1): quanto da cor do sistema a janela da tela de cima recebe; `0` = sempre `sheetBase`, igual para todo sistema | `ui/src/theme.cpp`, `ui/rnds/RndsUI.h`, `ui/rnds/RndsUI.cpp`, `docs/MAKE-A-THEME.md`, `system/rootfs/usr/share/banana/themes/README.txt` | O tema Frutiger Miku tem a janela de cima com cor fixa, sem mudar ao trocar de sistema |
| Imagem do cartão já com jogos e saves | `tools/make-full-image.sh` (arquivo novo, não muda o sistema) | Cartão novo pronto numa gravação só (ver "Cartão novo") |
| Atualizações pelo console vêm do meu fork | `system/rootfs/usr/libexec/banana/update` (linha `FEED=`), `tools/release.sh` (novo), `VERSION` | "Verificar atualizações" acha as releases da BananaMiku, não as oficiais |
| Tema Frutiger Miku vem com o sistema | `system/rootfs/usr/share/banana/themes/frutiger-miku.json` e `frutiger-miku/` (novos) | Aparece em Settings › Theme em toda instalação e atualização, sem copiar nada |

O tema vem dentro do sistema: mudanças nele (o `.json` ou as imagens em `frutiger-miku/`) chegam ao console na próxima
release. Um arquivo com o mesmo nome em `banana/themes/` no cartão **tem prioridade** sobre o do sistema: apagar
`banana/themes/frutiger-miku.json` do cartão para receber as versões novas. A cópia em `C:\Users\call1\BananaThemes\`
é só para editar; a versão oficial é a do repositório.

## Fluxo de cada versão nova

### 1. Merge do oficial

As minhas mudanças ficam em commits meus na `main` do meu fork, **BananaMiku** (`origin`, March93B/BananaMiku). O
projeto oficial é o remote `upstream` (JorreFog/BananaLinux).

```sh
git fetch upstream --tags
git merge v0.X.Y          # a tag da versão nova (ou upstream/main)
git push origin main
```

Num conflito nos arquivos da tabela acima, manter as duas coisas: o que veio do oficial e a minha mudança. Em
`VERSION` o conflito vem sempre: ficar com a versão oficial nova e somar o meu número (ver o passo 2).

### 2. Compilar (no Linux)

Neste PC: no WSL (`Ubuntu-24.04`, já com as dependências), como o usuário `builder`, num clone em
`/home/builder/BananaMiku` (a build não funciona dentro de `/mnt/c`). Ele não é a mesma pasta do Windows: levar as
mudanças com `git pull` (do GitHub ou do caminho `/mnt/c/...`). E rodar com o PATH limpo, porque o do Windows tem
espaços e o Buildroot recusa:

```sh
wsl -d Ubuntu-24.04 -u builder --cd /home/builder/BananaMiku -- env -i HOME=/home/builder LANG=C.UTF-8 PATH=/usr/sbin:/usr/bin:/sbin:/bin make rgds-plus
```

Se a build for interrompida (queda de energia), apagar a pasta do pacote que estava compilando em
`output/rgds-plus/build/` e rodar de novo: ela continua de onde parou.

Antes, subir a versão em `VERSION` com **um número a mais** no fim: `0.5.3.6.1`, `0.5.3.6.2`... e, numa versão
oficial nova, `0.5.3.7.1`. O console compara número a número, então `0.5.3.6.1` é mais nova que `0.5.3.6`. Nunca
usar sufixo (`0.5.3.6-miku`): conta como versão de teste e fica *mais velha* que `0.5.3.6`. Commitar e dar push.

Debian/Ubuntu: `build-essential bc bison flex libssl-dev libelf-dev unzip rsync cpio python3-dev swig libgnutls28-dev`.

```sh
make test          # (opcional) o menu nos testes do projeto, sem o console
make rgds-plus     # a build inteira; a primeira leva uma hora ou mais
```

Sai em `output/rgds-plus/images/`:

- `banana-rgds-plus-<versão>.update.tar`: o pacote de atualização (**é este que eu uso**)
- `banana-rgds-plus.img.gz`: a imagem do cartão inteiro (**apaga tudo** no cartão; só para um cartão novo)

### 3. Publicar a release

Com o [GitHub CLI](https://cli.github.com) logado (`gh auth login`, uma vez):

```sh
sh tools/release.sh                          # release v<VERSION> na BananaMiku com o .update.tar e o SHA256SUMS
sh tools/release.sh --notes notas.md --image # com notas (o console mostra o 1º parágrafo) e a imagem do cartão
```

Ele confere que o pacote existe e tem a versão do `VERSION`, que o commit está no GitHub e que a tag ainda não
existe. `--prerelease` publica como versão de teste (o console só oferece com Settings › Test versions ligado).

### 4. Instalar no console (sem perder jogos e saves)

No console: Settings › System › Updates › Check for updates, baixar e instalar. Ele instala na outra partição de
sistema e vale a partir do próximo reinício. Jogos, saves, configurações e temas ficam. A versão anterior continua a
um reinício de distância (Settings › System › Previous version).

Sem Wi-Fi (ou a **primeira vez**, num console que ainda tem uma build que busca as releases oficiais): copiar o
`.update.tar` para `banana/updates/` no cartão e, em Settings › System › Update, A no pacote e A de novo.

O canal beta (Settings › Updates › Beta channel) continua sendo o do projeto oficial: deixar desligado.

### Cartão novo (já com jogos e saves)

`tools/make-full-image.sh` monta uma imagem com a partição `BANANA` já pronta e cheia: grava uma vez e o console
liga com tudo no lugar, sem copiar nada depois.

1. Copiar a unidade `BANANA` inteira do cartão atual para uma pasta (ex.: `backup-banana/`, com `roms/`, `bios/`,
   `saves/`, `states/`, `banana/`, `drastic/`, `superdrastic/`...) e levar para o Linux.
2. Medir o cartão **que vai receber** a imagem, em bytes exatos. No Windows (PowerShell):
   `Get-Disk | Format-Table Number, FriendlyName, Size`; no Linux: `lsblk -b`.
3. No Linux (precisa de `exfatprogs`, e de sudo):

   ```sh
   sh tools/make-full-image.sh output/rgds-plus/images/banana-rgds-plus.img.gz <tamanho em bytes> backup-banana/
   ```

4. Gravar `banana-rgds-plus-full.img` no cartão (Raspberry Pi Imager › Use custom image).

A partição de dados vai até o fim do cartão (exFAT não cresce depois), por isso o tamanho tem que ser o do cartão
certo: num cartão menor que o informado, a imagem não serve. A imagem só tem o sistema e os arquivos, então a gravação
leva o tempo de copiar os jogos, não o cartão inteiro.

Sem o script: gravar o `.img.gz`, ligar uma vez (o primeiro boot cria a partição `BANANA`) e copiar de volta as
pastas.

## Cuidados

- Desligar sempre pelo menu (nunca segurando o botão ou deixando a bateria acabar) e ejetar o cartão no Windows antes
  de tirar: senão a partição `BANANA` fica suja e os saves podem parar de gravar sem dar erro.
- Se o Windows mostrar a unidade `BANANA` com aviso: `chkdsk <letra>: /f` como administrador.
