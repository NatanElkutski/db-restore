# 🗄️ Railway Database Restore Guide

This guide covers how to manage, recreate, and restore your PostgreSQL database using the `db-restore` service and the `manage.sh` script.

---

## 🛠 Prerequisites
* **Railway CLI** installed and authenticated (`railway login`).
* **Linked Project**: Ensure you are in your project folder and run `railway link`.

---

## 1️⃣ Verify Your Environment
Before doing anything destructive, always verify you are in the **Staging** environment.
```bash
railway status
```

## 2️⃣ Access the Restore Toolbox
Since you cannot run the R2-streaming scripts from your local Windows machine, you must enter the "Restore" container.
```bash
railway ssh --service db-restore
```
*Once inside, verify you are in the right container:*
```bash
echo $RAILWAY_SERVICE_NAME
# Should output: db-restore
```

## 3️⃣ Create/Recreate the Database
If you have dropped your database or it doesn't exist, you must recreate it. Since your `$DATABASE_URL` might point to a non-existent DB, we connect to the system `postgres` database to run the create command.

```bash
psql "${DATABASE_URL%/*}/postgres" -c "CREATE DATABASE railway;"
```
> [!TIP]
> Change `railway` to your actual database name (e.g., `pwrdesk_backup`) if you are using a custom name.

## 4️⃣ Manage & Restore Backups
Use the `manage.sh` script to interact with your Cloudflare R2 backups.

### List all available backups
```bash
./manage.sh list
```

### Restore the LATEST backup
This is the fastest "one-click" way to get the most recent data.
```bash
./manage.sh restore
```

### Restore a SPECIFIC backup
If you need to go back to a specific point in time, copy the key from the list command.
```bash
./manage.sh restore backups/backup-2026-04-09_17-54.sql.gz
```

---

## 💡 Manual/Local Restore (Alternative)
If you have a backup file downloaded to your **local computer** and want to push it to a local Postgres instance (not Railway), use this command:

```bash
gunzip -c backups_backup-2026-04-09_17-54.sql.gz | psql -U postgres -d pwrdesk_backup
```

---

## ⚠️ Troubleshooting
* **Permission Denied**: If the scripts won't run inside the container, run `chmod +x *.sh`.
* **Database is being accessed by other users**: If the script fails to drop the schema, ensure your app service is temporarily stopped or hibernated so it releases its connection.
* **Connection Refused**: Double-check that your `DATABASE_URL` and R2 credentials are correctly set in the Railway service variables.
