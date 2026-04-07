# DB Restore Runbook

How to restore a Postgres dump from Cloudflare R2 into the Railway Postgres database, using the `db-restore` toolbox service on Railway.

> Assumes one-time setup is already done: GitHub repo with the scripts, `db-restore` service deployed on Railway, R2 and `DATABASE_URL` env variables set, Railway CLI installed locally (`npm install -g @railway/cli`).

---

## ⚠️ Before you run this

- [ ] Confirm you actually want to restore. This **drops and replaces** the `public` schema on the target database. Anything not in the dump is gone.
- [ ] Confirm `DATABASE_URL` on the `db-restore` service points to the **correct** Postgres (prod vs. test). Check it in the Railway dashboard → `db-restore` → Variables tab before proceeding.
- [ ] Tell your team production is going into maintenance, if applicable.
- [ ] Know which dump you want to restore from — usually the most recent one from **before** the incident, not necessarily the absolute newest.

---

## Step 1 — Open PowerShell

Start menu → **PowerShell** (regular, no admin needed).

## Step 2 — Log in to Railway

```powershell
railway login
```

A browser tab opens. Click **Authorize**. Come back to PowerShell — you should see a success message.

If you logged in recently, this may be a no-op and skip straight to confirming you're already logged in. That's fine.

## Step 3 — SSH into the `db-restore` service

If you already linked a folder with `railway link` previously, just `cd` to it and run:

```powershell
cd C:\railway-restore
railway ssh
```

**If that doesn't work** (or you haven't linked a folder), use the dashboard shortcut:

1. Go to railway.app → open your project.
2. **Right-click** the `db-restore` service tile → **Copy SSH Command**.
3. Paste into PowerShell and press enter.

You're in when your prompt changes to something like:

```
root@abc123:/app#
```

That prefix means you're now inside the Railway container, not on Windows anymore.

## Step 4 — Disable the AWS CLI pager (for this session)

The container's `aws` CLI tries to pipe output through `less`, which isn't installed. Turn it off:

```bash
export AWS_PAGER=""
```

No output means success.

> **Permanent fix:** add `ENV AWS_PAGER=""` to the `Dockerfile` in the GitHub repo and push — Railway rebuilds and you never need this step again.

## Step 5 — List available backups

```bash
./list-backups.sh
```

You should see a table of dump files in the R2 bucket, newest first, with timestamps and sizes. Something like:

```
|  2026-04-07T23:00:14+00:00 |  4821334 |  backups/2026-04-07.sql.gz  |
|  2026-04-06T23:00:09+00:00 |  4805112 |  backups/2026-04-06.sql.gz  |
...
```

**Copy the key** (the last column) of the dump you want to restore.

## Step 6 — Run the restore

```bash
./restore.sh backups/2026-04-07.sql.gz
```

Replace the filename with the key you copied.

The script will:

1. Confirm the dump exists in R2.
2. Show a warning with the target database (credentials masked).
3. Ask you to type `RESTORE` to confirm.
4. Drop + recreate the `public` schema.
5. Stream the dump from R2 and load it.

**At the prompt, type exactly:** `RESTORE` (uppercase), then press enter.

Wait until you see:

```
✅ Restore complete.
```

## Step 7 — Verify the restore worked

Still in the container:

```bash
psql "$DATABASE_URL" -c "\dt"
```

This lists all tables — they should be the ones you expect.

Spot-check a few row counts against what the backup should contain:

```bash
psql "$DATABASE_URL" -c "SELECT COUNT(*) FROM users;"
psql "$DATABASE_URL" -c "SELECT COUNT(*) FROM <other-important-table>;"
```

If numbers look right, the restore succeeded.

## Step 8 — Exit and bring the app back up

Leave the container:

```bash
exit
```

Your prompt returns to `PS C:\...>`. You're back on Windows.

If you put the app in maintenance mode, restart / unpause your app service(s) in the Railway dashboard and verify the app is healthy.

---

## Troubleshooting quick reference

| Problem | Fix |
|---|---|
| `export: The term 'export' is not recognized` | You're in PowerShell, not the container. Run `railway ssh` again — prompt should change to `root@...:/app#`. |
| `Unable to redirect output to pager ... 'less'` | Run `export AWS_PAGER=""` before the script. |
| `ERROR: object not found` | Typo in the dump key. Re-run `./list-backups.sh` and copy the key exactly. |
| `ERROR: cannot detect format from filename` | Dump filename isn't `.sql`, `.sql.gz`, `.dump`, or `.dump.gz`. Rename in R2. |
| `Could not connect to the endpoint URL ...s3.auto.amazonaws.com...` | `R2_ACCOUNT_ID` env var is wrong on the `db-restore` service. Fix in Variables tab. |
| `password authentication failed` | `DATABASE_URL` on `db-restore` is stale. Check it references the right Postgres service. |
| `railway ssh` says no deployments | The `db-restore` service isn't running. Check Deployments tab — if it crashed, check the logs. |
| SSH session disconnects mid-restore | Reconnect with `railway ssh` and re-run. The schema drop is idempotent, so re-running is safe. |

---

## The whole thing in 6 commands

Once you've done this once, the muscle memory is:

```powershell
railway login                         # Windows PowerShell
railway ssh                           # (or paste the copied SSH command)
export AWS_PAGER=""                   # now inside the container
./list-backups.sh
./restore.sh backups/<dump-key>       # type RESTORE when prompted
psql "$DATABASE_URL" -c "\dt"
```

That's it. Keep this file in the `pwrdesk-db-restore` repo next to the scripts so you always know where to find it.
