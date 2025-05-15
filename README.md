# 🔁 migrate-scheduler-jobs

This project contains a Bash script to migrate Google Cloud Scheduler jobs between projects, preserving configurations such as headers, body, and retry policies. Ideal for environments with multiple projects (e.g., dev and prod).

---

## 🗂️ Project structure

```bash
.
├── script_source_to_target.sh     # Main script for migrating jobs between projects
├── schedulers.json                # Stores exported jobs in JSON format
```

## ⚙️ Prerequisites

- Google Cloud SDK (gcloud) installed and authenticated.
- `jq` installed for reading JSON files.
- Sufficient permissions on both source and destination projects (Cloud `Scheduler Admin`, `Service Account User`, `Permission to list and create jobs`).

---

## 🚀 How to use

###  Step 1️⃣: Configure script parameters

Open the script_source_to_target.sh file and set the following variables:
```bash
  SOURCE_PROJECT=""
  DESTINATION_PROJECT=""
  SOURCE_LOCATION=""
  DESTINATION_LOCATION=""
```
### Step 2️⃣: Run the script

Execute the script:

```bash
  bash script_source_to_target.sh
```

The script will:

- List all jobs in the source project and location.
- Prompt you to confirm whether to copy each job.
- Export the original job JSON.
- SStore a copy in the `schedulers.json` file.
- Dynamically generate the command to recreate the job in the target project, including:
URI, HTTP Method, Body (base64 decoded), HTTP Headers, Retry policy, Timezone, Schedule, Description.
- Pause the original job after creation (and the new one, if it was already paused).

---

## 💡 Additional features

- Avoids overwriting existing jobs in the target project.
- Validates JSON with `jq` before taking action.
- Ensures headers are correctly concatenated using a single `--headers`.
- Properly handles `base64-encoded` bodies.
- Applies the original job’s `retryConfig`.

## 🛡️ Safety and reliability

- The script requires confirmation before copying each job.
- Existing jobs in the destination project are detected and skipped with a warning.
- All exported jobs are saved in schedulers.json.
- Original jobs are paused to prevent duplicate execution.

---


## ℹ️ Notes

- The script currently supports only HTTP-type jobs.
- Be sure to review headers and body of each job in `schedulers.json` before creating them in the destination.

---

## 📄 Example of exported JSON
```json
  {
    "name": "projects/meu-projeto-dev/locations/us-east1/jobs/job-de-exemplo",
    "schedule": "*/5 * * * *",
    "timeZone": "America/Sao_Paulo",
    "httpTarget": {
      "uri": "https://exemplo.com/processar",
      "httpMethod": "POST",
      "headers": {
        "Content-Type": "application/json"
      },
      "body": "eyJ0ZXN0IjogInZhbG9yIn0="
    }
  }
```
---

## ✅ Execution example

```bash
vim migrate_scheduler_jobs.sh  # Configure environment variables
bash migrate_scheduler_jobs.sh
```
