job "registry_browser" {
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

  group "browser" {
    task "browser" {
      driver = "docker"

      config {
        image       = "klausmeyer/docker-registry-browser:latest"
        dns_servers = ["10.10.2.136"]

        port_map {
          http = 8080
        }
      }

      env {
        NO_SSL_VERIFICATION  = "true"
        DOCKER_REGISTRY_URL  = "https://registry.service.consul"
        ENABLE_DELETE_IMAGES = "true"
      }

      resources {
        memory = 200
        cpu    = 500

        network {
          port "http" {}
        }
      }

      service {
        name = "registry-browser"

        tags = [
          "urlprefix-registry-browser.service.consul:9999/",
          "urlprefix-registry-browser.service.consul:443/",
        ]

        port = "http"

        check {
          type     = "tcp"
          interval = "20s"
          timeout  = "10s"
        }
      }
    }
  }
}
