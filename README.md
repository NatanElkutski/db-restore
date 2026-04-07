# Disaster Recovery: Restore Postgres from Cloudflare R2 to Railway

This toolkit restores a Postgres dump stored in Cloudflare R2 into a Railway Postgres database. Use it when production is broken and you need to roll back to a known-good backup.

> ⚠️ **Destructive.** The restore drops the `public` schema before loading the dump. Any data not in the dump is permanently lost. Read the whole guide before running anything against production.

## What's in this folder

| File | Purpose |
|---|---|
| `restore.sh` | Main script. Downloads a dump from R2 and restores it. |
| `list-backups.sh` | Lists available dumps in your R2 bucket. |
| `Dockerfile` | Builds a "toolbox" container for running restores inside Railway. |
| `.env.example` | Template for the environment variables the scripts need. |

## Before you start: gather these values

1. **Cloudflare R2 credentials.** Dashboard → R2 → *Manage R2 API Tokens* → create a token with read access to your backup bucket. Copy the Access Key ID and Secret Access Key. Also note your Account ID (top-right of the Cloudflare dashboard).
2. **R2 bucket name.** E.g. `pwrdesk-db-backup`.
3. **Target `DATABASE_URL`.** In Railway → your Postgres service → *Variables* tab → copy `DATABASE_URL`.
4. **The dump filename** you want to restore. You'll list these in Step 2.

---

## Choose your path

There are two ways to run the restore. Pick one:

- **Path A — Local machine.** Fastest to set up. Good for small/medium databases (under ~1 GB). The dump streams R2 → your laptop → Railway, so it's limited by your upload speed.
- **Path B — Toolbox service on Railway.** More setup, but the dump streams entirely inside Railway/Cloudflare's networks. Use this for large databases or if your internet is slow.

---

## Path A — Run from your local machine

### Step 1. Install the tools you need

**macOS (Homebrew):**
```bash
brew install awscli libpq
brew link --force libpq     # makes psql and pg_restore available
```

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install awscli postgresql-client
```

**Windows:** use WSL2 and follow the Ubuntu instructions.

Verify:
```bash
aws --version
psql --version
pg_restore --version
```

### Step 2. Set environment variables

Copy `.env.example` to `.env` and fill in your values. Then load them:

```bash
cp .env.example .env
# edit .env with your editor
set -a && source .env && set +a
```

Make the scripts executable:
```bash
chmod +x restore.sh list-backups.sh
```

### Step 3. List available backups

```bash
./list-backups.sh
```

You'll see something like:

```
------------------------------------------------------------------
|                        ListObjectsV2                           |
+----------------------------+----------+------------------------+
|  2026-04-07T23:00:14+00:00 |  4821334 |  backups/2026-04-07.sql.gz |
|  2026-04-06T23:00:09+00:00 |  4805112 |  backups/2026-04-06.sql.gz |
|  2026-04-05T23:00:11+00:00 |  4799881 |  backups/2026-04-05.sql.gz |
+----------------------------+----------+------------------------+
```

Pick the key (the last column) of the dump you want. **Generally you want the most recent one from *before* the disaster happened** — not just the newest, since the newest might already contain the bad state.

### Step 4. Run the restore

```bash
./restore.sh backups/2026-04-07.sql.gz
```

You'll see a warning and be asked to type `RESTORE` to confirm. Type it exactly, then press enter.

The script will:
1. Verify the dump exists in R2.
2. Detect the format from the filename (`.sql`, `.sql.gz`, `.dump`, `.dump.gz`).
3. Drop and recreate the `public` schema in the target DB.
4. Stream the dump from R2 directly into `psql` (or `pg_restore` for custom-format dumps).

When it finishes, you'll see `✅ Restore complete.`

### Step 5. Verify

Connect to the DB and spot-check:
```bash
psql "$DATABASE_URL" -c "\dt"                       # list tables
psql "$DATABASE_URL" -c "SELECT COUNT(*) FROM users;"   # or whatever tables you care about
```

Row counts should match what you expect from the backup time.

---

## Path B — Toolbox service on Railway

Use this when you have a large database, slow internet, or just want the restore to run entirely inside Railway's network.

### Step 1. Put these files in a git repo

Create a new repo (or a new folder in an existing one) containing `restore.sh`, `list-backups.sh`, and `Dockerfile`. Commit and push.

### Step 2. Create the Railway service

1. In your Railway project, click **New Service** → **GitHub Repo** → pick the repo from Step 1.
2. Railway auto-detects the Dockerfile and builds the image. The container runs `sleep infinity` so it stays up and you can shell into it.

### Step 3. Add environment variables to the service

In the toolbox service → *Variables* tab, add:

| Variable | Value |
|---|---|
| `R2_ACCOUNT_ID` | your Cloudflare account ID |
| `R2_ACCESS_KEY_ID` | from R2 API token |
| `R2_SECRET_ACCESS_KEY` | from R2 API token |
| `R2_BUCKET` | e.g. `pwrdesk-db-backup` |
| `DATABASE_URL` | reference your Postgres service's variable: `${{ Postgres.DATABASE_URL }}` |

The `${{ Postgres.DATABASE_URL }}` syntax tells Railway to pull the value from your Postgres service dynamically — replace `Postgres` with whatever your DB service is actually named.

Deploy/redeploy so the vars take effect.

### Step 4. Shell into the service and run the restore

In the Railway dashboard → toolbox service → click the running deployment → **Shell** tab (or use `railway shell` from the CLI).

```bash
./list-backups.sh
./restore.sh backups/2026-04-07.sql.gz
```

Same flow as Path A — you'll be asked to type `RESTORE` to confirm.

### Step 5. Verify (same as Path A)

```bash
psql "$DATABASE_URL" -c "\dt"
```

### Step 6. Turn the service off (optional but recommended)

You don't need the toolbox running 24/7. In the toolbox service → *Settings* → pause/remove the service when you're done. Keep the repo around so you can redeploy it next time.

---

## Troubleshooting

**`Could not connect to the endpoint URL: ...s3.auto.amazonaws.com...`**
Your backup script has `AWS_REGION=auto` set for something other than R2. `auto` is only valid for the R2 endpoint. This script uses `R2_ACCOUNT_ID` to build the right endpoint — you shouldn't see this error when using `restore.sh`.

**`ERROR: object not found`**
The key you passed doesn't exist. Run `./list-backups.sh` and copy the key exactly — it's case-sensitive and must include any `backups/` prefix.

**`ERROR: cannot detect format from filename`**
The script needs one of these extensions: `.sql`, `.sql.gz`, `.dump`, `.dump.gz`. If your dumps have a different name, either rename them in R2 or tell me and I'll add the extension you use.

**`pg_restore: error: input file does not appear to be a valid archive`**
You have a `.dump`-extensioned file that's actually plain SQL (or vice versa). Check how your backup was created: `pg_dump -Fc` produces custom format (`.dump`), plain `pg_dump` produces SQL (`.sql`). Rename the file in R2 to match its real format.

**Restore takes forever / times out from local machine**
Switch to Path B (toolbox service).

**"password authentication failed" against the target DB**
Double-check `DATABASE_URL`. In Railway, grab it fresh from the Postgres service — if you rotated it recently, your local `.env` may be stale.

---

## Safety checklist before running against production

- [ ] I have identified the correct dump file (from *before* the disaster).
- [ ] I have confirmed `DATABASE_URL` points to the right database (not staging by mistake, not a DB I care about).
- [ ] I understand the `public` schema will be dropped and replaced.
- [ ] I have told my team production is going into maintenance.
- [ ] I have a plan to verify the restore worked (row counts, spot checks).
- [ ] If possible, I have tested the same `restore.sh` command against a throwaway DB first.

An untested backup is not a backup. If this is the first time you're running this, **please** spin up a second Railway Postgres service, point `DATABASE_URL` at it, and do a dry run before you ever need it for real.
