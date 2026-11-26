# Postgres: banco dos apps do hetzner

Um Postgres só (`postgres:17-alpine`) para os apps do servidor, cada um com o seu banco e o seu
usuário. Substitui o Neon: lá o compute era cobrado por tempo ligado e um app com worker nunca
deixava o banco dormir; aqui ele custa só a memória do container.

```text
hetzner
  rede edge (overlay do Swarm, a mesma das stacks e do Caddy)
    ├─ postgres:5432            Komodo Deployment `postgres`, sem porta publicada
    │    volume postgres-data   dados
    │    /opt/postgres/init     10-apps.sh: cria banco e usuário por app (Ansible)
    │    /opt/postgres/backups  pg_dumpall diário, 14 dias (cron do Ansible)
    └─ hetzner_acerola-sync_server  → postgres://acerola_sync:…@postgres:5432/acerola_sync
```

## Arquivos

| Arquivo | Vai para | O quê |
|---|---|---|
| `.komodo/komodo.toml` | Komodo (Sync `postgres`) | o Deployment: imagem, rede, volume, variáveis |
| `config/init-apps.sh` | `/opt/postgres/init/10-apps.sh` | cria `role` + `database` por variável `PGAPP_<APP>_PASSWORD` |
| `ansible/deploy.yml` | etapa `postgres` | diretórios, script, cron do backup e roda o script no container |
| `ansible/clean.yml` | clean `postgres` | remove o container; com `remove_volumes`, os dados e os backups |

## Segredos (Komodo → Variables, secretas)

| Variável | Para quê |
|---|---|
| `POSTGRES_PASSWORD` | superusuário `postgres` (só administração) |
| `ACEROLA_SYNC_DB_PASSWORD` | usuário `acerola_sync`; a mesma senha vai na `ACEROLA_SYNC_DATABASE_URL` do acerola-sync |

## Subir pela primeira vez

1. Crie as duas Variables no Komodo.
2. Actions → **Ansible Deploy** → `hetzner`, etapa `postgres` (prepara `/opt/postgres`).
3. Komodo → Syncs → `postgres` → **Execute** (o Deployment sobe e o `10-apps.sh` roda no primeiro boot).
4. Conferir: `docker exec postgres psql -U postgres -Atc "\l acerola_sync"`.

## Acrescentar um app

1. Variable secreta `<APP>_DB_PASSWORD` no Komodo.
2. Linha `PGAPP_<APP>_PASSWORD=[[<APP>_DB_PASSWORD]]` no `environment` do Deployment (este repo, `main`).
3. Redeploy do `postgres` no Komodo e etapa `postgres` do Ansible de novo (ela roda o script no
   container; o entrypoint só roda sozinho no primeiro boot).
4. No app, `DATABASE_URL=postgres://<app>:<senha>@postgres:5432/<app>` e a stack na rede `edge`.

O nome do app vira minúsculo: `PGAPP_MEU_APP_PASSWORD` → usuário e banco `meu_app`.

## Backup e restauração

Todo dia às 04:15 UTC o cron grava `/opt/postgres/backups/AAAA-MM-DD.sql.gz` (`pg_dumpall`) e
apaga o que tem mais de 14 dias. Para restaurar um banco:

```bash
zcat /opt/postgres/backups/2026-11-25.sql.gz | docker exec -i postgres psql -U postgres
```

Para trazer dados de outro Postgres (um `pg_dump` do Neon, por exemplo):

```bash
pg_dump "<url de origem>" --no-owner --no-privileges --data-only | docker exec -i postgres psql -U acerola_sync -d acerola_sync
```

## Cuidados

- Sem porta publicada: só quem está na rede `edge` chega nele. Para administrar, `docker exec`.
- `--memory=256m`, `shared_buffers=64MB`, `max_connections=40`: o servidor tem 3,5 GB para tudo.
  Se um app precisar de mais, suba os três juntos.
- Trocar a imagem de versão maior (17 → 18) exige `pg_dumpall` antes e restauração depois: o
  volume de dados não é compatível entre versões maiores.
