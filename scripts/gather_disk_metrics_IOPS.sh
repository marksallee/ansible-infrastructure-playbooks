#!/bin/bash

# ==============================================================================
# Test your VM to see how it performs on pd-ssd versus pd-balanced disk.
# ==============================================================================

# How to use this for comparison
## Before Switching (On PD-SSD): Run the script during your expected peak loads. For example, to run it for 10 minutes (600 seconds) on disk sdb:
## 
## ./gather_disk_metrics.sh 600 dbname postgres_user sdc
## This will generate a file like /tmp/db_metrics_report_2026-04-02_14-00-00.log. Rename or copy this file somewhere safe (e.g., pd_ssd_peak_tuesday.log).
## 
## After Switching (On PD-Balanced): Once the migration is done, run the script again during a similar workload period.
## 
## ./gather_disk_metrics.sh 600 dbname postgres_user sdc
## This generates a new log file. Rename or copy it (e.g., pd_balanced_peak_wednesday.log).
## 
## Proving the IOPs are adequate: Open both text files side-by-side.
## 
## If Total Average IOPS on the PD-Balanced disk easily supported the workload (it will be far below the 80,000 max limit of PD-Balanced disks).
## If Average Disk Latency (await) remains roughly the same (sub-millisecond to a few milliseconds).
## If Average CPU IOWait doesn't spike significantly.
## And most importantly, if TPS and Average Active DB Requests handled the business load without backing up...
## ...then you have concrete, empirical proof in log form that the PD-Balanced disk is performing identically to the PD-SSD for your database's specific I/O profile.

# CONFIGURATION
# Adjust these variables if your setup uses different names or devices
# ==============================================================================
DURATION=${1:-60}          # How long to run the test (in seconds)
DB_NAME=${2:-dbname}     # Name of the database to monitor
DB_USER=${3:-postgres_user}     # Postgres user executing the queries
DISK_DEVICE=${4:-sdc}      # Your GCP data disk device (e.g., sda, sdb, nvme0n1)
# ==============================================================================

# Create timestamped directory for this run's data
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
RUN_DIR="/tmp/db_metrics_run_${TIMESTAMP}"
REPORT_FILE="/tmp/db_metrics_report_${TIMESTAMP}.log"

mkdir -p "$RUN_DIR"

# Redirect all standard output and standard error from the report generation 
# to BOTH the screen (via tee) and the permanent log file.
{
    echo "=================================================="
    echo " Starting Disk & DB Metrics Gathering ($DURATION sec)"
    echo " Timestamp: $TIMESTAMP"
    echo " Database: $DB_NAME | User: $DB_USER | Disk: $DISK_DEVICE"
    echo " Output Directory: $RUN_DIR"
    echo " Report File: $REPORT_FILE"
    echo "=================================================="

    # Dependency checks
    command -v iostat >/dev/null 2>&1 || { echo >&2 "Missing 'iostat'. Please install 'sysstat' package. Aborting."; exit 1; }
    command -v vmstat >/dev/null 2>&1 || { echo >&2 "Missing 'vmstat'. Aborting."; exit 1; }
    command -v psql >/dev/null 2>&1 || { echo >&2 "Missing 'psql'. Aborting."; exit 1; }

    # 1. Snapshot Initial DB Transactions
    echo "[1/4] Capturing initial database state..."
    TX_START=$(psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "SELECT xact_commit + xact_rollback FROM pg_stat_database WHERE datname = '$DB_NAME';")
    if [ -z "$TX_START" ]; then
        echo "Error: Could not connect to PostgreSQL. Check your credentials or database name."
        exit 1
    fi

    # 2. Gather OS Metrics (IOPS & IOWait) in the background
    echo "[2/4] Gathering IOPS and CPU IOWait in the background..."
    iostat -dx "$DISK_DEVICE" 1 "$DURATION" > "$RUN_DIR/iostat_metrics.out" &
    IOSTAT_PID=$!

    vmstat 1 "$DURATION" > "$RUN_DIR/vmstat_metrics.out" &
    VMSTAT_PID=$!

    # 3. Poll Active DB Requests
    echo "[3/4] Polling active database requests..."
    ACTIVE_REQS_FILE="$RUN_DIR/db_active_reqs.out"
    > "$ACTIVE_REQS_FILE"

    # Poll the database every 2 seconds
    POLL_INTERVAL=2
    ITERATIONS=$((DURATION / POLL_INTERVAL))

    for (( i=1; i<=ITERATIONS; i++ )); do
        psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND backend_type = 'client backend';" >> "$ACTIVE_REQS_FILE"
        sleep $POLL_INTERVAL
    done

    # Wait for background OS metric gathering to finish
    wait $IOSTAT_PID
    wait $VMSTAT_PID

    # 4. Snapshot Final DB Transactions
    echo "[4/4] Capturing final database state..."
    TX_END=$(psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "SELECT xact_commit + xact_rollback FROM pg_stat_database WHERE datname = '$DB_NAME';")

    # ==============================================================================
    # CALCULATE RESULTS
    # ==============================================================================
    echo ""
    echo "=================================================="
    echo " METRICS REPORT: $TIMESTAMP (Test Duration: $DURATION seconds)"
    echo " Disk Device: $DISK_DEVICE | Target DB: $DB_NAME"
    echo "=================================================="

    # --- Database Metrics ---
    TX_DIFF=$((TX_END - TX_START))
    TPS=$(awk "BEGIN { printf \"%.2f\", $TX_DIFF / $DURATION }")
    AVG_ACTIVE_REQS=$(awk '{ total += $1; count++ } END { if (count > 0) printf "%.2f", total/count; else print 0 }' "$ACTIVE_REQS_FILE")

    echo "[ Database Metrics ]"
    echo " - Total Transactions Processed : $TX_DIFF"
    echo " - Transactions Per Second (TPS): $TPS"
    echo " - Average Active DB Requests   : $AVG_ACTIVE_REQS"

    # --- OS / Disk Metrics ---
    # vmstat CPU wait column (wa is typically column 16). Skip first 3 lines.
    AVG_IOWAIT=$(awk 'NR>3 { total += $16; count++ } END { if (count > 0) printf "%.2f", total/count; else print 0 }' "$RUN_DIR/vmstat_metrics.out")

    # iostat r/s (col 4) and w/s (col 5), await (col 10). Skip first report (NR>1).
    AVG_READ_IOPS=$(grep "^$DISK_DEVICE" "$RUN_DIR/iostat_metrics.out" | awk 'NR>1 { total += $4; count++ } END { if(count>0) printf "%.2f", total/count; else print 0}')
    AVG_WRITE_IOPS=$(grep "^$DISK_DEVICE" "$RUN_DIR/iostat_metrics.out" | awk 'NR>1 { total += $5; count++ } END { if(count>0) printf "%.2f", total/count; else print 0}')
    AVG_LATENCY=$(grep "^$DISK_DEVICE" "$RUN_DIR/iostat_metrics.out" | awk 'NR>1 { total += $10; count++ } END { if(count>0) printf "%.2f", total/count; else print 0}')

    echo ""
    echo "[ Infrastructure Metrics (Disk: $DISK_DEVICE) ]"
    echo " - Average CPU IOWait           : $AVG_IOWAIT %"
    echo " - Average Disk Latency (await) : $AVG_LATENCY ms"
    echo " - Average Read IOPS (r/s)      : $AVG_READ_IOPS"
    echo " - Average Write IOPS (w/s)     : $AVG_WRITE_IOPS"
    echo " - Total Average IOPS           : $(awk "BEGIN { print $AVG_READ_IOPS + $AVG_WRITE_IOPS }")"
    echo "=================================================="
    echo "Raw data saved to: $RUN_DIR/"
    echo "Report saved to:   $REPORT_FILE"

} | tee "$REPORT_FILE"
