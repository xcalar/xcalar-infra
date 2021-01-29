job "gitlab" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"

  update {
    max_parallel      = 1
    min_healthy_time  = "10s"
    progress_deadline = "20m"
    healthy_deadline  = "10m"
    auto_revert       = false
    canary            = 0
  }

  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "10m"
  }

  group "gitlab" {
    count = 1

    constraint {
      operator = "distinct_hosts"
      value    = "true"
    }

    restart {
      attempts = 10
      interval = "5m"
      delay    = "30s"
    }

    ephemeral_disk {
      sticky = true
      size   = 300
    }

    #    restart {
    #      attempts = 5
    #      interval = "5m"
    #      delay    = "15s"
    #    }

    task "gitlab" {
      driver = "docker"

      config {
        image = "gitlab/gitlab-ce:latest"

        force_pull = true

        volumes = [
          "/netstore/infra/gitlab/config:/etc/gitlab",
          "/netstore/infra/gitlab/logs:/var/log/gitlab",
          "/netstore/infra/gitlab/data:/var/opt/gitlab",
        ]

        port_map {
          ui_port = 80

          #ssl_port = 443
          ssh_port = 22
        }
      }

      template {
        destination = "secret/secret.env"

        data = <<EOD
{{range $i, $e := service "redis" "any"}}
REDIS_HOST={{$e.Address}}
REDIS_PORT={{$e.Port}}{{end}}
EOD
      }

      resources {
        memory = 8000
        cpu    = 6000

        network {
          port "ui_port" {}

          #port "ssl_port"{}
          port "ssh_port" {
            static = "22122"
          }
        }
      }

      service {
        name = "gitlab"
        port = "ui_port"

        tags = [
          "urlprefix-gitlab.service.consul:443/",
          "urlprefix-gitlab.int.xcalar.com:443/",
        ]

        check {
          type = "tcp"

          #path     = "/service/rest/v1/status"
          port     = "ui_port"
          interval = "20s"
          timeout  = "5s"
        }
      }

      service {
        name = "gitlab-ssh"
        port = "ssh_port"

        check {
          type     = "tcp"
          interval = "20s"
          timeout  = "10s"
        }
      }
    }
  }
}
