# Ansible Infrastructure Playbooks

Infrastructure automation playbooks focused on repeatable deployment, environment-aware configuration, and workflow across Linux, PostgreSQL, GCP and virtualized environments.

This repository is designed to demonstrate practical infrastructure automation steps inspired by on-the-job scenarios.

## Technologies
Ansible
PostgreSQL
Google Cloud Platform (GCP)
Linux administration

See working example playbook + role at:
  ansible-infrastructure-playbooks/roles/gcp_snapshot_restore/tasks/main.yml 
  
with its calling playbook, playbooks/gcp_snapshot_restore.yml.  



## Example of how this script was used

- Take a snapshot of a postgres disk. Have the option to delete a disk and recreate it from a specific snapshot. Useful for replicating production data on a test system to ensure data recovery and quality. Ensure that postgres service works correctly on restart. 

## Other scripts that were useful around the same time

In scripts/:  

gather_disk_metrics_IOPS.sh	- Check iostat, vmstat and postgres transactions to gather metrics on how a disk is performing.  

lvm_add_new_disk.md - Steps used to modify the LVM disk configuration when downsizing to a smaller data disk and recopying the data.  

