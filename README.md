# Ansible Infrastructure Playbooks

Infrastructure automation playbooks focused on repeatable deployment, environment-aware configuration, and workflow across Linux, PostgreSQL, GCP and virtualized environments.

This repository is designed to demonstrate practical infrastructure automation steps inspired by on-the-job scenarios.

## Technologies
Ansible
PostgreSQL
Google Cloud Platform (GCP)
Linux administration

See working example playbook + role at:
  ansible-infrastructure-playbooks/roles/gcp_snapshot_restore/tasks/main.yml with its calling playbook, playbooks/gcp_snapshot_restore.yml.  

```

## How this script was used

- Restore postgres data from production onto a dev environment so the developers can test with recent data.

- Take a snapshot of a postgres disk. Have the option to delete a disk and recreate it from a specific snapshot. Useful for replicating production data on a test system to ensure data recovery and quality. Ensure that postgres works correctly on restart. 

