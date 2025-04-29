chmod +x install_node_slurm_exporter.sh

Node Exporter is serving metrics at http://localhost:9100/metrics
Slurm Exporter is serving metrics at http://localhost:8080/metrics

=======================================================
Installation Summary:
=======================================================
Node Exporter:
  - Version: 1.7.0
  - Service status: active
  - Binary location: /usr/local/bin/node_exporter
  - Metrics endpoint: http://localhost:9100/metrics
  - Run as user: node_exporter

Slurm Exporter:
  - Version: Built from source
  - Service status: active
  - Binary location: /usr/local/bin/prometheus-slurm-exporter
  - Metrics endpoint: http://localhost:8080/metrics
  - Run as user: slurm_exporter


To verify, you can run: curl http://localhost:9100/metrics
Or for Slurm Exporter: curl http://localhost:8080/metrics
