job "redisinsight" {
  datacenters = ["xcalar-sjc"]
  type        = "service"

  update {
    max_parallel     = 1
    min_healthy_time = "10s"
    healthy_deadline = "5m"
    auto_revert      = false
    canary           = 0
  }

  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }

  group "redisinsight" {
    task "redisinsight" {
      driver = "docker"

      config {
        image       = "redislabs/redisinsight:latest"
        force_pull  = true
        dns_servers = ["10.10.2.136"]

        port_map {
          http = 8001
        }
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 256 # 256MB

        network {
          port "http" {}
        }
      }

      service {
        name = "redisinsight"
        tags = ["urlprefix-redisinsight.service.consul:443/"]
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
