# deadhand

> Fork de [nedorazrab0/abootloop](https://github.com/Magisk-Modules-Alt-Repo/abootloop) (MIT).
> Módulo Magisk / KernelSU. Uma única função: **apagar o aparelho** quando o botão
> **Power** é pressionado **4x rapidamente**.

---

## ☢ AVISO - LEIA ANTES DE QUALQUER COISA

**Este módulo destrói TODOS os dados do aparelho. O resultado é CATASTRÓFICO e IRREVERSÍVEL.**

- Não existe "desfazer".
- Não existe recuperação dos dados depois que ele dispara: as chaves de criptografia
  são destruidas, então o conteúdo vira ruido matematico. Nem forense recupera.
- Um disparo acidental tem o mesmo custo de um disparo real: **o aparelho zerado**.
- O botão Power é pressionado o dia inteiro sem querer. Trate este módulo com o mesmo
  respeito de uma ferramenta que apaga discos. Porque é o que ele é.

Se você não tem **certeza absoluta** de que quer isto, **não arme e não ponha em modo real.**
Você é a única pessoa responsável pelo que acontece com o seu aparelho.

**Faca backup do que importa ANTES de armar.** Depois não da.

---

## O que ele faz

Quando **armado** e em **modo real**, ao detectar **4 toques no Power** dentro de uma
janela curta (padrão 1,5 s), o deadhand:

1. **Crypto-shred**: sobrescreve e apaga o material de chave da criptografia do Android
   (FBE em `/data/misc/vold`, chave de metadata em `/metadata`, keystore, gatekeeper).
   Isso torna o `userdata` ilegível **na hora**, de forma irreversível.
2. **Factory reset**: grava o comando `--wipe_data` no BCB (bloco de controle do
   bootloader, partição `misc`) e reinicia no recovery, que formata o `userdata`.

### Por que assim, e não "sobrescrever com dd"

Em armazenamento moderno (eMMC/UFS com wear-leveling e overprovisioning) sobrescrever a
partição **não garante** apagar: sobram copias fisicas fora do alcance do `dd`, é lento e
desgasta o flash. Em Android 10+ (FBE / metadata encryption) o caminho de **qualidade** é
o **crypto-shred**: destruir as chaves AES envolvidas pelo TEE. Sem chave, o ciphertext é
irrecuperável no mesmo instante. O factory reset entra como segundo mecanismo (o que o
sistema chama de "apagar tudo"). Cinto e suspensório.

---

## Freios de segurança (todos ligados por padrão)

Porque a ação é irreversível, o módulo nasce **travado** e exige passos conscientes para
ficar perigoso:

| Freio | Padrão | O que faz |
|---|---|---|
| **Desarmado** (`ARMED=0`) | ligado | Os 4x Power **não fazem nada**. Precisa armar de propósito. |
| **Simulação** (`DRY_RUN=1`) | ligado | Mesmo armado, os 4x Power só **vibram e escrevem no log** "APAGARIA AGORA". Não apaga. |
| **Janela de aborto** (`ABORT_SECONDS=5`) | ligado | Depois do 4o toque, há 5 s para **cancelar com VOL+ ou VOL-**. |
| **Anti-repique** (`DEBOUNCE_MS=120`) | ligado | Ignora toques colados demais (repique do botão) para não contar falso. |
| **Janela apertada** (`WINDOW_MS=1500`) | ligado | Os 4 toques precisam caber em 1,5 s, senão a contagem zera. |

Para o módulo apagar de verdade é preciso, **de propósito**: armar **e** por `DRY_RUN=0`.
Dois interruptores separados, para que nenhum acidente sozinho seja suficiente.

---

## Instalação

1. Instale o zip pelo Magisk ou KernelSU (Módulos > Instalar do armazenamento).
2. Reinicie. O daemon sobe sozinho no boot (mas **desarmado** e em **simulação**).

Ele não pede nada na instalação e não mexe em nada até ser armado.

---

## Uso (na ordem, sem pular etapa)

### 1. Teste em simulação (obrigatório antes do modo real)

1. Arme pelo botão **Action** do gerenciador (Magisk/KSU) na tela do módulo. Como
   `DRY_RUN=1`, isto é seguro.
2. De 4 toques rápidos no Power.
3. Confira o log:

   ```
   su -c 'tail -f /data/adb/deadhand/deadhand.log'
   ```

   Deve aparecer `APAGARIA AGORA (nenhuma acao tomada)`. Se aparecer, a detecção funciona
   no **seu** aparelho. Se não aparecer, ajuste `WINDOW_MS`/`DEBOUNCE_MS` no config e teste
   de novo. **Nunca** va para o modo real sem ver o disparo no log em simulação.

### 2. Ir para o modo real (perigoso)

Só depois de validar em simulação:

```sh
su -c 'sed -i "s/^DRY_RUN=.*/DRY_RUN=0/" /data/adb/deadhand/config'
```

A partir daqui, com o módulo **armado**, 4x Power **apagam o aparelho** (respeitando a
janela de aborto).

### 3. Armar / desarmar no dia a dia

Use o botão **Action** na tela do módulo (Magisk/KSU). Ele alterna armado/desarmado e
mostra o estado atual + as ultimas linhas do log. Deixe **desarmado** sempre que não
estiver em situação que justifique o risco.

---

## Configuração

Arquivo: `/data/adb/deadhand/config`

| Chave | Padrão | Descrição |
|---|---|---|
| `ARMED` | `0` | `1` arma. Prefira o botão Action. |
| `DRY_RUN` | `1` | `1` simula (so loga). `0` = **modo real, apaga**. |
| `WINDOW_MS` | `1500` | Janela total para os 4 toques (ms). |
| `DEBOUNCE_MS` | `120` | Ignora toques mais juntos que isto (ms). |
| `ABORT_SECONDS` | `5` | Janela para cancelar com VOL+/VOL-. `0` desliga (não recomendado). |
| `WIPE_REASON` | `deadhand` | Rótulo gravado no comando do recovery. |

`ARMED` e `DRY_RUN` valem na hora. Mudou os outros? reinicie (o daemon le no boot).

---

## Como cancelar um disparo em andamento

Depois do 4o toque, enquanto durar `ABORT_SECONDS`, aperte **VOL+ ou VOL-**. O aparelho
vibra ao entrar na janela de aborto. Passou a janela sem cancelar, o wipe começa e **não
da mais para parar**.

---

## Desinstalar

Remova o módulo pelo gerenciador e reinicie. Opcional, apague o estado:

```sh
su -c 'rm -rf /data/adb/deadhand'
```

---

## Limitações e responsabilidade

- Detecção de tecla depende de `getevent`; teste **sempre** em simulação no seu aparelho.
- A gravação do BCB e o crypto-shred variam por fabricante/ROM. O crypto-shred já torna os
  dados irrecuperáveis mesmo que o factory reset do recovery falhe.
- Não há garantia de qualquer tipo (ver LICENSE). O uso é **por sua conta e risco**. O
  autor não se responsabiliza por perda de dados, uso indevido ou disparo acidental.
- Não instale isto em aparelho que não seja seu, nem em aparelho de outra pessoa sem o
  consentimento explicito e informado dela.

---

## Créditos

Fork de **abootloop** de [nedorazrab0](https://github.com/Magisk-Modules-Alt-Repo/abootloop),
sob licença MIT. A estrutura de detecção de teclas via `getevent` vem de la; o gatilho de
4x Power, o crypto-shred, o factory reset e os freios de segurança são deste fork.
