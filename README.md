# deadhand

> Fork de [nedorazrab0/abootloop](https://github.com/Magisk-Modules-Alt-Repo/abootloop) (MIT).
> Modulo Magisk / KernelSU. Uma unica funcao: **apagar o aparelho** quando o botao
> **Power** e' pressionado **4x rapidamente**.

---

## ☢ AVISO - LEIA ANTES DE QUALQUER COISA

**Este modulo destroi TODOS os dados do aparelho. O resultado e' CATASTROFICO e IRREVERSIVEL.**

- Nao existe "desfazer".
- Nao existe recuperacao dos dados depois que ele dispara: as chaves de criptografia
  sao destruidas, entao o conteudo vira ruido matematico. Nem forense recupera.
- Um disparo acidental tem o mesmo custo de um disparo real: **o aparelho zerado**.
- O botao Power e' pressionado o dia inteiro sem querer. Trate este modulo com o mesmo
  respeito de uma ferramenta que apaga discos. Porque e' o que ele e'.

Se voce nao tem **certeza absoluta** de que quer isto, **nao arme e nao ponha em modo real.**
Voce e' a unica pessoa responsavel pelo que acontece com o seu aparelho.

**Faca backup do que importa ANTES de armar.** Depois nao da.

---

## O que ele faz

Quando **armado** e em **modo real**, ao detectar **4 toques no Power** dentro de uma
janela curta (padrao 1,5 s), o deadhand:

1. **Crypto-shred**: sobrescreve e apaga o material de chave da criptografia do Android
   (FBE em `/data/misc/vold`, chave de metadata em `/metadata`, keystore, gatekeeper).
   Isso torna o `userdata` ilegivel **na hora**, de forma irreversivel.
2. **Factory reset**: grava o comando `--wipe_data` no BCB (bloco de controle do
   bootloader, particao `misc`) e reinicia no recovery, que formata o `userdata`.

### Por que assim, e nao "sobrescrever com dd"

Em armazenamento moderno (eMMC/UFS com wear-leveling e overprovisioning) sobrescrever a
particao **nao garante** apagar: sobram copias fisicas fora do alcance do `dd`, e' lento e
desgasta o flash. Em Android 10+ (FBE / metadata encryption) o caminho de **qualidade** e'
o **crypto-shred**: destruir as chaves AES envolvidas pelo TEE. Sem chave, o ciphertext e'
irrecuperavel no mesmo instante. O factory reset entra como segundo mecanismo (o que o
sistema chama de "apagar tudo"). Cinto e suspensorio.

---

## Freios de seguranca (todos ligados por padrao)

Porque a acao e' irreversivel, o modulo nasce **travado** e exige passos conscientes para
ficar perigoso:

| Freio | Padrao | O que faz |
|---|---|---|
| **Desarmado** (`ARMED=0`) | ligado | Os 4x Power **nao fazem nada**. Precisa armar de proposito. |
| **Simulacao** (`DRY_RUN=1`) | ligado | Mesmo armado, os 4x Power so **vibram e escrevem no log** "APAGARIA AGORA". Nao apaga. |
| **Janela de aborto** (`ABORT_SECONDS=5`) | ligado | Depois do 4o toque, ha 5 s para **cancelar com VOL+ ou VOL-**. |
| **Anti-repique** (`DEBOUNCE_MS=120`) | ligado | Ignora toques colados demais (repique do botao) para nao contar falso. |
| **Janela apertada** (`WINDOW_MS=1500`) | ligado | Os 4 toques precisam caber em 1,5 s, senao a contagem zera. |

Para o modulo apagar de verdade e' preciso, **de proposito**: armar **e** por `DRY_RUN=0`.
Dois interruptores separados, para que nenhum acidente sozinho seja suficiente.

---

## Instalacao

1. Instale o zip pelo Magisk ou KernelSU (Modulos > Instalar do armazenamento).
2. Reinicie. O daemon sobe sozinho no boot (mas **desarmado** e em **simulacao**).

Ele nao pede nada na instalacao e nao mexe em nada ate ser armado.

---

## Uso (na ordem, sem pular etapa)

### 1. Teste em simulacao (obrigatorio antes do modo real)

1. Arme pelo botao **Action** do gerenciador (Magisk/KSU) na tela do modulo. Como
   `DRY_RUN=1`, isto e' seguro.
2. De 4 toques rapidos no Power.
3. Confira o log:

   ```
   su -c 'tail -f /data/adb/deadhand/deadhand.log'
   ```

   Deve aparecer `APAGARIA AGORA (nenhuma acao tomada)`. Se aparecer, a deteccao funciona
   no **seu** aparelho. Se nao aparecer, ajuste `WINDOW_MS`/`DEBOUNCE_MS` no config e teste
   de novo. **Nunca** va para o modo real sem ver o disparo no log em simulacao.

### 2. Ir para o modo real (perigoso)

So depois de validar em simulacao:

```sh
su -c 'sed -i "s/^DRY_RUN=.*/DRY_RUN=0/" /data/adb/deadhand/config'
```

A partir daqui, com o modulo **armado**, 4x Power **apagam o aparelho** (respeitando a
janela de aborto).

### 3. Armar / desarmar no dia a dia

Use o botao **Action** na tela do modulo (Magisk/KSU). Ele alterna armado/desarmado e
mostra o estado atual + as ultimas linhas do log. Deixe **desarmado** sempre que nao
estiver em situacao que justifique o risco.

---

## Configuracao

Arquivo: `/data/adb/deadhand/config`

| Chave | Padrao | Descricao |
|---|---|---|
| `ARMED` | `0` | `1` arma. Prefira o botao Action. |
| `DRY_RUN` | `1` | `1` simula (so loga). `0` = **modo real, apaga**. |
| `WINDOW_MS` | `1500` | Janela total para os 4 toques (ms). |
| `DEBOUNCE_MS` | `120` | Ignora toques mais juntos que isto (ms). |
| `ABORT_SECONDS` | `5` | Janela para cancelar com VOL+/VOL-. `0` desliga (nao recomendado). |
| `WIPE_REASON` | `deadhand` | Rotulo gravado no comando do recovery. |

`ARMED` e `DRY_RUN` valem na hora. Mudou os outros? reinicie (o daemon le no boot).

---

## Como cancelar um disparo em andamento

Depois do 4o toque, enquanto durar `ABORT_SECONDS`, aperte **VOL+ ou VOL-**. O aparelho
vibra ao entrar na janela de aborto. Passou a janela sem cancelar, o wipe comeca e **nao
da mais para parar**.

---

## Desinstalar

Remova o modulo pelo gerenciador e reinicie. Opcional, apague o estado:

```sh
su -c 'rm -rf /data/adb/deadhand'
```

---

## Limitacoes e responsabilidade

- Deteccao de tecla depende de `getevent`; teste **sempre** em simulacao no seu aparelho.
- A gravacao do BCB e o crypto-shred variam por fabricante/ROM. O crypto-shred ja torna os
  dados irrecuperaveis mesmo que o factory reset do recovery falhe.
- Nao ha garantia de qualquer tipo (ver LICENSE). O uso e' **por sua conta e risco**. O
  autor nao se responsabiliza por perda de dados, uso indevido ou disparo acidental.
- Nao instale isto em aparelho que nao seja seu, nem em aparelho de outra pessoa sem o
  consentimento explicito e informado dela.

---

## Creditos

Fork de **abootloop** de [nedorazrab0](https://github.com/Magisk-Modules-Alt-Repo/abootloop),
sob licenca MIT. A estrutura de deteccao de teclas via `getevent` vem de la; o gatilho de
4x Power, o crypto-shred, o factory reset e os freios de seguranca sao deste fork.
