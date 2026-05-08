# Ansible Infrastructure Playbooks

Infrastructure automation playbooks focused on repeatable deployment, environment-aware configuration, and workflow across Linux, PostgreSQL, GCP and virtualized environments.

This repository is designed to demonstrate practical infrastructure automation steps inspired by on-the-job scenarios.

## Technologies
Ansible
PostgreSQL
Google Cloud Platform (GCP)
Linux administration


## Repository Structure
```
inventory/  
  dev/  
  staging/  
  prod/  

playbooks/  
  postgres/  
  gcp/  
  system/  

roles/  
  postgres/  
  common/  
  monitoring/  

docs/
```

## Goal
Restore postgres data from production onto a dev environment so the developers can test with recent data.

Most of my recent work has been inside private systems at work, so this repo focuses on recreating and demonstrating the workflows using sanitized examples that could apply generically to other environments.
