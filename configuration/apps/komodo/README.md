# Komodo: painel de deploy dos servidores

[Komodo](https://komo.do) v2: um painel (Core) gerencia o Docker de todos os servidores por um agente
(Periphery) em cada um. Os stacks vêm do git e cada um escolhe o servidor onde roda.

Trazido do repositório `grupo-azuos/server`. Lá o painel escuta no IP do NetBird; aqui ele segue o
padrão da Oracle: sem porta publicada, entregue pelo Caddy em `komodo.<domain>` com `vpn_only`.

```text
oracle
  Caddy  komodo.vinicius-gpl.com   painel e agentes só pela VPN; /listener/* público (webhooks)
    └─ Komodo Core + Mongo (/opt/komodo, rede proxy)
        ▲
        │ WebSocket autenticado por par de chaves (o agente é quem conecta)
        │
oracle  → ws://komodo-core:9120 (mesmo Docker)
hetzner → wss://komodo.vinicius-gpl.com pela VPN (Ansible)
pluto   → wss://komodo.vinicius-gpl.com pela VPN (docker compose desta pasta)
  Komodo Periphery   sem porta publicada; age no Docker local, stacks e repos em /etc/komodo
```

## Arquivos

| Arquivo | Vai para | Onde roda |
|---|---|---|
| `compose.core.yml` | `/opt/komodo` | oracle |
| `config/secrets.env.j2` | `/opt/komodo/secrets.env` | gerado uma vez, nunca sobrescrito |
| `config/komodo.caddy` | `/opt/caddy/conf.d/` | oracle (também em `caddy_sites` do `vars.yml`) |
| `compose.periphery.yml` | `/opt/komodo-periphery` | todo servidor com agente |
| `config/periphery.env.j2` | `/opt/komodo-periphery/periphery.env` | endereço do Core, nome e onboarding key |
| `periphery.env.example` | `periphery.env` (não versionado) | agente fora do Ansible (PLUTO) |

As versões ficam no `vars:` do `deploy.yml` (`komodo_version`, `komodo_mongo_version`), assim como
`komodo_core_address` (padrão `wss://komodo.vinicius-gpl.com`; a Oracle sobrescreve no `vars.yml`).

## Variáveis do `hosts.ini`

| Variável | Onde | Para quê |
|---|---|---|
| `komodo_admin_password` | oracle | senha do `admin` (só vale na primeira subida) |
| `komodo_db_password` | oracle | senha do Mongo (só vale na criação do volume; sem ela, é sorteada) |
| `komodo_jwt_secret` | oracle | assinatura das sessões do painel (sem ela, é sorteada) |
| `komodo_webhook_secret` | oracle | segredo dos webhooks do GitHub (o mesmo vai no webhook do repo) |
| `komodo_onboarding_key` | todo servidor com agente | registra o agente no painel (criada no painel) |
| `komodo_server_name` | opcional | nome no painel; padrão é o hostname (a Oracle usa `oracle`) |

Para a etapa `all` também subir o Komodo, use `komodo_enabled=true` / `komodo_periphery_enabled=true`.

## Deploy

Pré-requisitos: Caddy e NetBird já rodando na Oracle; os outros servidores já são peers do NetBird
com a rota `oracle-public-ip` (é o que faz o `vpn_only` deixar o agente passar). Registro A `komodo`
na Cloudflare, só DNS, com o IP da Oracle.

**1. Painel**: Actions → **Ansible Deploy** → servidor `oracle`, etapa `komodo`. Ou localmente:

```bash
ansible-playbook -i configuration/servers/oracle/hosts.ini configuration/ansible/deploy.yml \
  -e @configuration/servers/oracle/vars.yml --tags komodo
```

Conferir (na VPN): `https://komodo.vinicius-gpl.com`, login `admin`.

**2. Onboarding key (manual)**: no painel, **Settings → Onboarding**, crie uma chave reutilizável e
coloque em `komodo_onboarding_key` no `hosts.ini` (secret `ANSIBLE_HOSTS_INI`) de cada servidor.

**3. Agentes**: etapa `komodo-periphery` em `oracle` e `hetzner`. No PLUTO:

```bash
cd configuration/apps/komodo
cp periphery.env.example periphery.env    # preencha a onboarding key
sudo mkdir -p /etc/komodo
docker compose -f compose.periphery.yml up -d
```

Cada agente aparece em **Servers**. Depois do primeiro registro a onboarding key não é mais necessária.

Os segredos vão para `/opt/komodo/secrets.env` só na primeira subida (o arquivo nunca é
sobrescrito). Para trocar um deles depois, apague o arquivo e rode a etapa de novo. A senha do Mongo
não pode mudar depois que o volume já existe.

## Swarm, builders e apps

**Regra: todo app builda no servidor onde roda. Não existe registry (sem GHCR, sem push, sem pull).**
O Builder `oracle` constrói os apps da Oracle e o Builder `hetzner` os do hetzner. A imagem fica só
local (`<app>:<commit>`) e a stack sobe com `--resolve-image never`.

O my-config só conhece a infraestrutura. Ela está em [`.komodo/komodo.toml`](../../../.komodo/komodo.toml),
na raiz do repo:

| Recurso | O quê |
|---|---|
| Sync `config` | aplica o próprio arquivo (webhook no push da `main`) |
| Swarm `oracle`, `hetzner` | um Swarm de um nó por servidor (o Ansible faz o `swarm init`, etapa `swarm`) |
| Builder `oracle`, `hetzner` | cada servidor constrói as próprias imagens |
| Deployments `netbird-*`, `element-*` e `postgres` | NetBird (oracle), Element Call + Web e o Postgres dos apps (hetzner). Imagem pronta de registry vira Deployment; app buildado do repo vira Build + Stack. O Ansible gera configs e segredos, o Komodo roda os containers |

O Caddy é um container comum: ele alcança as stacks pela rede overlay `edge` (attachable), que o
Ansible cria e na qual conecta o Caddy.

**Cada app** tem o próprio `.komodo/komodo.toml` no repo dele, com Repo, Build, Stack, Procedure,
Action (rollback) e Sync. Ele aponta para `swarm = "<servidor>"`, `builder = "<servidor>"` e a rede
`edge`. A rota do app no Caddy é gravada pelo próprio deploy (`post_deploy` da Stack). O my-config
não sabe nada dos apps.

- **Nomes**: `<servidor>_<app>` (ex.: `acerola_relay`, `oracle_erp-personal`).
- **Tags**: `env:<servidor>` e `app:<nome>` em todo recurso.
- **Webhooks no GitHub de cada app**: só dois. O da Sync
  (`https://komodo.vinicius-gpl.com/listener/github/sync/<sync>/sync`) e o da Procedure
  (`https://komodo.vinicius-gpl.com/listener/github/procedure/<servidor>_<app>/main`). Use JSON,
  evento *push* e o `komodo_webhook_secret` como segredo. Build e Stack não têm webhook: é a
  Procedure que chama os dois.
- **Segredos dos apps**: Variables secretas do Komodo, usadas como `[[NOME]]`.

**Primeira vez**: crie à mão a Sync `config` (repo `vinicius-gpl/config`, branch `main`,
resource path `.komodo/komodo.toml`) e execute. Para o Element, rode antes as etapas `element-call`
e `element-web` do Ansible no hetzner (geram as configs que os Deployments montam) e, depois do
deploy, `element-call` de novo para criar o usuário admin.
## Replicar o Komodo (o mesmo setup em outro lugar)

- **Outro servidor como painel**: rode a etapa `komodo` nele (com `komodo_admin_password` e o
  `komodo.caddy` em `caddy_sites`) e aponte os agentes para ele com `komodo_core_address`.
- **Copiar os dados de um Core para outro** (stacks, servidores, usuários): o Komodo grava backups
  datados em `/etc/komodo/backups`; restaure um deles no Mongo do Core novo
  ([docs](https://komo.do/docs/setup/backup)). Ou exporte os recursos como TOML no painel
  (**Syncs**) e importe no outro.
- **Trocar de Core** muda o par de chaves: apague o volume `komodo-periphery-keys` dos agentes e
  refaça o onboarding (ver Cuidados).

## Remover

Actions → **Ansible Clean** → `komodo` ou `komodo-periphery` (*remove_volumes* apaga banco/chaves).
O `/etc/komodo` dos servidores fica: lá estão os stacks publicados e os backups do banco.

## Cuidados

- **O agente controla o Docker inteiro do servidor** (equivale a root). Ele não publica porta e o
  painel só aceita origem da VPN. Mantenha assim.
- **Chaves.** O Core guarda o par de chaves no volume `komodo-keys`; cada agente grava a chave
  pública do Core na primeira conexão e passa a exigir a mesma. Se o volume do Core for apagado,
  os agentes recusam o Core novo: apague também o `komodo-periphery-keys` deles e refaça o onboarding.
- **Memória.** A Oracle tem pouca RAM; o Mongo está limitado a 0,25 GB de cache. Se apertar, troque
  para o FerretDB (`compose/ferretdb.compose.yaml` oficial). Mongo 5+ exige CPU com AVX.
