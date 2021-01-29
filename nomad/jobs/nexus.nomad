job "nexus" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"

  update {
    max_parallel      = 1
    min_healthy_time  = "10s"
    healthy_deadline  = "3m"
    progress_deadline = "10m"
    auto_revert       = false
    canary            = 0
  }

  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }

  group "sonatype" {
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

    task "nexus3" {
      driver = "docker"

      config {
        image      = "sonatype/nexus3:latest"
        force_pull = true

        volumes = [
          "/netstore/infra/nexus3/_data:/nexus-data",
          "secret/secret.env:/secret.env",
        ]

        port_map {
          ui_port       = 8081
          registry_port = 5000
        }
      }

      env {
        INSTALL4J_ADD_VM_PARAMS = "-Xms1000m -Xmx3000m -XX:MaxDirectMemorySize=3g -Djava.util.prefs.userRoot=/nexus-data/javaprefs -Djava.awt.headless=true"
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
        memory = 4000
        cpu    = 4000

        network {
          port "ui_port"{}
          port "registry_port"{}
        }
      }

      service {
        name = "nexus"
        port = "ui_port"

        tags = [
          "urlprefix-nexus.service.consul:443/",
          "urlprefix-nexus.int.xcalar.com:443/",
        ]

        #"urlprefix-nexus.int.xcalar.com:443/",

        check {
          type     = "http"
          path     = "/service/rest/v1/status"
          port     = "ui_port"
          interval = "1m"
          timeout  = "20s"
        }
      }

      service {
        name = "nexus-registry"
        port = "registry_port"

        tags = [
          "urlprefix-nexus-registry.service.consul:5000/",
          "urlprefix-nexus-registry.service.consul:443/",
        ]

        check {
          type     = "tcp"
          interval = "20s"
          timeout  = "10s"
        }
      }
    }
  }
}
