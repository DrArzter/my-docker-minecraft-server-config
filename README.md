# Minecraft server profiles

Authoring source for several Minecraft server configurations based on
[`itzg/docker-minecraft-server`](https://github.com/itzg/docker-minecraft-server). A profile describes one playable
server runtime: Minecraft version, loader, Compose configuration and the source mod list. Runtime worlds, downloaded
JARs and secrets are deliberately not stored in Git.

## Profiles

| ID | Gameplay | Runtime |
| --- | --- | --- |
| `main` | Current modded server | Minecraft 1.20.1, Forge 47.4.10, CurseForge source list |
| `vanilla-forge` | Vanilla-like, no mods | Minecraft 1.20.1 on Forge 47.4.10 |

Vanilla gameplay does not require the vanilla loader. Keeping Forge with an empty mod directory is a valid profile and
makes later addition of server-only utility mods possible without changing the world's runtime family.

Each profile is self-contained below `profiles/<id>/`:

```text
profile.json    machine-readable identity and loader/mod contract
compose.yaml    standalone local runtime
.env.example    names of required secrets; copy to .env
extras/         authoring inputs such as the CurseForge list, when applicable
data/           generated world/runtime data, ignored by Git
mods/           downloaded mod cache, ignored by Git
```

A profile is not just a different list placed under an existing save. Each selectable server in Spawnpoint gets its
own world directory and backup lineage. This prevents opening a modded save with the wrong pack and losing modded
blocks or dimensions.

## Run locally

```bash
cd profiles/main
cp .env.example .env
# Fill CF_API_KEY and RCON_PASSWORD.
docker compose up -d
```

Or start the empty-mod Forge profile:

```bash
cd profiles/vanilla-forge
cp .env.example .env
# Fill RCON_PASSWORD.
docker compose up -d
```

Only one profile can bind local port `25565` at a time. Stop the active profile before starting another one. Because
their `data/` directories differ, stopping one and starting another cannot silently reuse its world.

Validate every profile without starting containers:

```bash
scripts/validate-profiles.sh
```

The original root command remains temporarily compatible and still starts the main configuration:

```bash
cp profiles/main/.env.example .env
docker compose up -d
```

New automation should use `profiles/main/compose.yaml` directly. The root `docker-compose.yml` exists only to avoid a
flag-day migration of existing local data.

## Source versus release

CurseForge URLs are convenient authoring inputs but are not immutable releases. Spawnpoint resolves a profile into an
exact release containing file IDs, sizes and SHA-256 hashes. Those hashes remain the deployment truth; descriptive mod
names and versions are metadata. Do not commit downloaded JARs or put API keys in profile files.
