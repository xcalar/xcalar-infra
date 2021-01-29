job "prometheus" {
  datacenters = ["xcalar-sjc"]
  type        = "service"

  constraint {
    attribute    = "${meta.localstore}"
    set_contains = "ssd"
  }

  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    healthy_deadline = "3m"
    auto_revert      = false
    canary           = 0
  }

  group "monitoring" {
    count = 1

    restart {
      attempts = 10
      interval = "5m"
      delay    = "25s"
      mode     = "fail"
    }

    ephemeral_disk {
      size   = "300"
      sticky = true
    }

    task "loki" {
      driver = "docker"

      config {
        image      = "grafana/loki:latest"
        force_pull = true

        args = ["-config.file=/etc/loki/local-config.yaml"]
      }

      resources {
        network {
          port "loki_ui" {
            static = "3100"
          }
        }

        cpu    = 4000
        memory = 250
      }

      service {
        name = "loki-ui"
        port = "loki_ui"

        tags = ["urlprefix-loki-ui.nomad:9999/", "urlprefix-loki-ui.service.consul:9999/"]

        check {
          name     = "loki_ui port alive"
          type     = "tcp"
          interval = "20s"
          timeout  = "5s"
        }
      }
    }

    #### GRAPHITE EXPORTER  ####
    #    task "graphite-exporter" {
    #      driver = "docker"
    #
    #      config {
    #        image = "prom/graphite-exporter"
    #
    #        force_pull = true
    #
    #        volumes = [
    #          "./local/graphite-mapping.conf:/tmp/graphite-mapping.conf",
    #        ]
    #
    #        args = ["--graphite.mapping-config=/tmp/graphite-mapping.conf"]
    #      }
    #
    #      resources {
    #        network {
    #          port "graphite_ui" {
    #            static = "9108"
    #          }
    #
    #          port "mgmnt" {
    #            static = "9109"
    #          }
    #        }
    #
    #        cpu    = 1000
    #        memory = 500
    #      }
    #
    #      service {
    #        name = "graphite"
    #        port = "graphite_ui"
    #
    #        tags = ["urlprefix-graphite.service.consul:9999/", "urlprefix-graphite.service.consul:9108/"]
    #
    #        check {
    #          name     = "graphite_ui port alive"
    #          type     = "tcp"
    #          interval = "20s"
    #          timeout  = "5s"
    #        }
    #      }
    #
    #      service {
    #        name = "mgmnt"
    #        port = "mgmnt"
    #
    #        tags = ["urlprefix-mgmnt.service.consul:9999/", "urlprefix-mgmnt.service.consul:443/"]
    #
    #        check {
    #          name     = "mgmnt port alive"
    #          type     = "tcp"
    #          interval = "20s"
    #          timeout  = "5s"
    #        }
    #      }
    #    }
    #
    #### GRAFANA #####
    task "grafana" {
      driver = "docker"

      config {
        image      = "grafana/grafana:latest"
        force_pull = true

        port_map {
          grafana_ui = 3000
        }

        volumes = [
          "/netstore/infra/grafana-ui/nomad/var/lib/grafana:/var/lib/grafana",
          "/netstore/infra/grafana-ui/nomad/etc/grafana:/etc/grafana",
          "secrets/credentials:/usr/share/grafana/.aws/credentials",
        ]
      }

      env {
        VAULT_ADDR         = "https://vault.service.consul:8200"
        AWS_DEFAULT_REGION = "us-west-2"
        AWS_REGION         = "us-west-2"
      }

      vault {
        policies    = ["aws", "aws-xcalar"]
        env         = true
        change_mode = "restart"
      }

      template {
        destination = "secrets/credentials"
        change_mode = "restart"

        data = <<EOT
[default]
region = us-west-2
{{ with secret "aws/sts/grafana-cloudwatch" "ttl=43200"}}
aws_access_key_id = {{ .Data.access_key }}
aws_secret_access_key = {{ .Data.secret_key }}
aws_session_token = {{ .Data.security_token }}{{ end }}
EOT
      }

      resources {
        cpu    = 6000
        memory = 1000

        network {
          port "grafana_ui" {}
        }
      }

      service {
        name = "grafana"
        port = "grafana_ui"

        tags = [
          "urlprefix-grafana.nomad:9999/",
          "urlprefix-grafana.service.consul:9999/",
          "urlprefix-grafana.service.consul:443/",
          "urlprefix-grafana.int.xcalar.com:443/",
        ]

        check {
          name     = "grafana_ui port alive"
          type     = "http"
          path     = "/api/health"
          interval = "20s"
          timeout  = "5s"
        }
      }
    }

    #### ALERT MANAGER #####
    task "alertmanager" {
      driver = "docker"

      config {
        image      = "prom/alertmanager:latest"
        force_pull = true

        volumes = [
          "local/alertmanager.yml:/etc/alertmanager/alertmanager.yml",
          "/netstore/infra/alertmanager/nomad:/alertmanager"
        ]

        args = [
          "--storage.path=/alertmanager/data",
          "--config.file=/etc/alertmanager/alertmanager.yml"
        ]

        port_map {
          alertmanager_ui = 9093
        }
      }

      resources {
        cpu = 1000
        memory = 250

        network {
          port "alertmanager_ui" {
            static = "9093"
          }
        }
      }

      service {
        name = "alertmanager"
        port = "alertmanager_ui"

        tags = [
          "urlprefix-alertmanager.service.consul:443/",
          "urlprefix-alertmanager.service.consul:9999/",
          "urlprefix-alertmanager.nomad:9999/",
        ]

        check {
          name     = "alertmanager_ui port alive"
          type     = "tcp"
          interval = "20s"
          timeout  = "5s"
        }
      }

      template {
        change_mode   = "signal"
        change_signal = "SIGHUP"
        destination   = "local/alertmanager.yml"

        data = <<HERE
---
global:
  # The smarthost and SMTP sender used for mail notifications.
  smtp_smarthost: {{ env "NOMAD_IP_alertmanager_ui" }}:25
  smtp_require_tls: false
  smtp_from: 'alertmanager@xcalar.com'

## The directory from which notification templates are read.
#templates:
#  - '/alertmanager/template/*.tmpl'

# The root route on which each incoming alert enters.
route:
  # The root route must not have any matchers as it is the entry point for
  # all alerts. It needs to have a receiver configured so alerts that do not
  # match any of the sub-routes are sent to someone.
  #receiver: 'team-X-mails'
  receiver: rstephens-email

  # The labels by which incoming alerts are grouped together. For example,
  # multiple alerts coming in for cluster=A and alertname=LatencyHigh would
  # be batched into a single group.
  group_by: ['alertname', 'job']

  # When a new group of alerts is created by an incoming alert, wait at
  # least 'group_wait' to send the initial notification.
  # This way ensures that you get multiple alerts for the same group that start
  # firing shortly after another are batched together on the first
  # notification.
  group_wait: 1m

  # When the first notification was sent, wait 'group_interval' to send a batch
  # of new alerts that started firing for that group.
  group_interval: 5m

  # If an alert has successfully been sent, wait 'repeat_interval' to
  # resend them.
  repeat_interval: 3h

### CHILD ROUTES ###
#  # The child route trees.
#  routes:
#  # This routes performs a regular expression match on alert labels to
#  # catch alerts that are related to a list of services.
#  - match_re:
#      service: ^(foo1|foo2|baz)$
#    receiver: team-X-mails
#    # The service has a sub-route for critical alerts, any alerts
#    # that do not match, i.e. severity != critical, fall-back to the
#    # parent node and are sent to 'team-X-mails'
#    routes:
#    - match:
#        severity: critical
#      receiver: team-X-pager
#  - match:
#      service: files
#    receiver: team-Y-mails
#
#    routes:
#    - match:
#        severity: critical
#      receiver: team-Y-pager
#
#  # This route handles all alerts coming from a database service. If there's
#  # no team to handle it, it defaults to the DB team.
#  - match:
#      service: database
#    receiver: team-DB-pager
#    # Also group alerts by affected database.
#    group_by: [alertname, cluster, database]
#    routes:
#    - match:
#        owner: team-X
#      receiver: team-X-pager
#      continue: true
#    - match:
#      owner: team-Y
#      receiver: team-Y-pager
#
## Inhibition rules allow to mute a set of alerts given that another alert is
## firing.
## We use this to mute any warning-level notifications if the same alert is
## already critical.
#inhibit_rules:
#- source_match:
#    severity: 'critical'
#  target_match:
#    severity: 'warning'
#  # Apply inhibition if the alertname is the same.
#  equal: ['alertname']

# For now, everything to me.
receivers:
- name: 'rstephens-email'
  email_configs:
  - to: 'rstephens@xcalar.com'

#- name: 'team-X-mails'
#  email_configs:
#  - to: 'team-X+alerts@example.org'
#
#- name: 'team-X-pager'
#  email_configs:
#  - to: 'team-X+alerts-critical@example.org'
#  pagerduty_configs:
#  - service_key: <team-x-key>
#
#- name: 'team-Y-mails'
#  email_configs:
#  - to: 'team-Y+alerts@example.org'
#
#- name: 'team-Y-pager'
#  pagerduty_configs:
#  - service_key: <team-y-key>
#
#- name: 'team-DB-pager'
#  pagerduty_configs:
#  - service_key: <team-db-key>
HERE
       }
    }

    #### PUSH GATEWAY #####
    task "pushgateway" {
      driver = "docker"

      config {
        image      = "prom/pushgateway:latest"
        force_pull = true

        volumes = [
          "/mnt/data/prometheus:/prometheus",
        ]

        args = ["--persistence.file=/prometheus/${NOMAD_JOB_NAME}-${NOMAD_GROUP_NAME}-${NOMAD_TASK_NAME}.pushgw"]

        port_map {
          pushgateway_ui = 9091
        }
      }

      resources {
        memory = 250

        network {
          port "pushgateway_ui" {
            static = "9091"
          }
        }
      }

      service {
        name = "pushgateway"
        port = "pushgateway_ui"

        tags = [
          "urlprefix-pushgateway.service.consul:443/",
          "urlprefix-pushgateway.nomad:9999/",
        ]

        check {
          name     = "pushgateway_ui port alive"
          type     = "tcp"
          interval = "20s"
          timeout  = "5s"
        }
      }
    }
    ### PROMETHEUS
    task "prometheus" {
      driver = "docker"

      config {
        image      = "prom/prometheus:latest"
        force_pull = true

        volumes = [
          "local/prometheus.yml:/etc/prometheus/prometheus.yml",
          "local/rules.yml:/etc/prometheus/rules.yml",
          "/mnt/data/prometheus:/prometheus",
        ]

        args = [
          "--config.file=/etc/prometheus/prometheus.yml",
          "--storage.tsdb.path=/prometheus",
          "--storage.tsdb.retention.time=30d",
          "--web.console.libraries=/usr/share/prometheus/console_libraries",
          "--web.console.templates=/usr/share/prometheus/consoles",
        ]

        port_map {
          prometheus_ui = 9090
        }
      }

      resources {
        cpu    = 4000
        memory = 2000

        network {
          port "prometheus_ui" {}
        }
      }

      service {
        name = "prometheus"
        port = "prometheus_ui"

        tags = [
          "urlprefix-prometheus.service.consul:9999/",
          "urlprefix-prometheus.nomad:9999/",
          "urlprefix-prometheus.service.consul:443/",
          "urlprefix-prometheus.int.xcalar.com:443/",
        ]

        check {
          name     = "prometheus_ui port alive"
          type     = "http"
          path     = "/-/healthy"
          interval = "20s"
          timeout  = "5s"
        }
      }

      template {
        change_mode   = "signal"
        change_signal = "SIGHUP"
        destination   = "local/rules.yml"
        data = <<HERE
---
groups:
- name: alert_test
  rules:
  - alert: AlertTest
    expr: alert_test > 0
- name: corefile_detected
  rules:
  - alert: CorefileDetected
    expr: corefile_detected > 0
HERE
      }

      template {
        change_mode   = "signal"
        change_signal = "SIGHUP"
        destination   = "local/prometheus.yml"

        data = <<EOH
---
global:
  scrape_interval: 15s
  scrape_timeout: 10s
  evaluation_interval: 15s

# Rule files specifies a list of globs. Rules and alerts are read from
# all matching files.
rule_files:
  - '/etc/prometheus/rules.yml'

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
          - localhost:9090
  - job_name: minio-job
    bearer_token: eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJleHAiOjQ3NDgxOTUzMjIsImlzcyI6InByb21ldGhldXMiLCJzdWIiOiJLM0NDMllNV0lHU1pWUjA5UTNXTyJ9.Q8T3YrHDirF3GnClLg8YYBcxs2zXNbg1CyQJLTWGM9blfmf5BlpHJ-5Kwfzm-EsdeQgsz0R-r__c7MNk3Mlsnw
    metrics_path: /minio/prometheus/metrics
    scheme: https
    tls_config:
      insecure_skip_verify: true
    static_configs:
    - targets: [minio.int.xcalar.com]
  - job_name: minioazure-job
    bearer_token: eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJleHAiOjQ3NDgxOTk5NDgsImlzcyI6InByb21ldGhldXMiLCJzdWIiOiJ4Y2RhdGFzZXRzd2VzdHVzMiJ9.1VtQDRCPza--0QFpvOWr0QPvl6f5qdtpn-zPuGnBVxlNtjzGvXizUNmQz2lOtRBtPfetzizqC9uHTEouPBu9CQ
    metrics_path: /minio/prometheus/metrics
    scheme: https
    tls_config:
      insecure_skip_verify: true
    static_configs:
    - targets: [minioazure.int.xcalar.com]
  - job_name: vsphere
    params:
      format:
        - prometheus
    metrics_path: /metrics
    scrape_interval: 1m
    scrape_timeout: 20s
    consul_sd_configs:
      - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
        datacenter: xcalar-sjc
        services: ["vsphere-exporter"]
  - job_name: ovirt
    params:
      format:
        - prometheus
    metrics_path: /metrics
    scrape_interval: 1m
    scrape_timeout: 20s
    consul_sd_configs:
      - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
        datacenter: xcalar-sjc
        services: ["ovirt-exporter"]
  - job_name: pushgateway
    params:
      format:
        - prometheus
    metrics_path: /metrics
    scrape_interval: 1m
    scrape_timeout: 20s
    honor_labels: true
    static_configs:
      - targets:
          - '{{ env "NOMAD_IP_prometheus_ui" }}:9091'
  - job_name: jenkins-exporter
    metrics_path: /prometheus
    params:
      format:
        - prometheus
    consul_sd_configs:
      - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
        datacenter: xcalar-sjc
        services: ["jenkins-exporter"]
  - job_name: loki
    metrics_path: /metrics
    params:
      format:
        - prometheus
    consul_sd_configs:
      - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
        datacenter: xcalar-sjc
        services: ["loki-ui"]
  - job_name: squid-exporter
    params:
      format:
        - prometheus
    consul_sd_configs:
      - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
        datacenter: xcalar-sjc
        services: ["squid-exporter"]
  - job_name: registry-exporter
    params:
      format:
        - prometheus
    consul_sd_configs:
      - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
        datacenter: xcalar-sjc
        services: ["registry-exporter"]
  - job_name: node-exporter
    params:
      format:
        - prometheus
    consul_sd_configs:
      - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
        datacenter: xcalar-sjc
        services: ["node-exporter"]
  - job_name: nomad
    metrics_path: /v1/metrics
    params:
      format:
        - prometheus
    consul_sd_configs:
      - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
        datacenter: xcalar-sjc
        services:
          - nomad
          - nomad-client
    relabel_configs:
    - source_labels: ['__meta_consul_tags']
      regex: '(.*)http(.*)'
      action: keep

alerting:
  alertmanagers:
  - scheme: http
    static_configs:
    - targets:
        - '{{ env "NOMAD_IP_prometheus_ui" }}:9093'
EOH
      }
    }
  }
}

#    relabel_configs:
#      - source_labels:
#          - __meta_consul_tags
#        regex: .*,http,.*
#        action: keep
#  - job_name: nomad_metrics
#    scrape_interval: 5s
#    metrics_path: /v1/metrics
#    params:
#      format:
#        - prometheus
#    consul_sd_configs:
#      - server: '{{ env "NOMAD_IP_prometheus_ui" }}:8500'
#        datacenter: xcalar-sjc
#        scheme: http
#        scheme: http
#        services:
#          - nomad-client
#          - nomad
#    tls_config:
#      insecure_skip_verify: true
#    relabel_configs:
#      - source_labels:
#          - __meta_consul_tags
#        separator: ;
#        regex: (.*)http(.*)
#        replacement: $1
#        action: keep
#      - source_labels:
#          - __meta_consul_address
#        separator: ;
#        regex: (.*)
#        target_label: __meta_consul_service_address
#        replacement: $1
#        action: replace

