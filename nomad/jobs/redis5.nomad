job "redis5" {
  datacenters = ["xcalar-sjc"]
  type        = "service"

  #  update {
  #    max_parallel      = 1
  #    min_healthy_time  = "10s"
  #    healthy_deadline  = "3m"
  #    progress_deadline = "10m"
  #    auto_revert       = false
  #    canary            = 0
  #  }
  #
  #  migrate {
  #    max_parallel     = 1
  #    health_check     = "checks"
  #    min_healthy_time = "10s"
  #    healthy_deadline = "5m"
  #  }

  group "redis5" {
    count = 1

    restart {
      attempts = 5
      interval = "5m"
      delay    = "15s"
    }

    ephemeral_disk {
      sticky  = true
      migrate = true
      size    = 300
    }


    task "redis5" {
      driver = "docker"

      config {
        image = "redis:5"

        volumes = [
          "/netstore/infra/redis5:/data",
        ]

        port_map {
          db = 6379
        }
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 256 # 256MB

        network {
          port "db" {}
        }
      }

      service {
        name = "redis5"
        tags = ["global", "cache", "kv"]
        port = "db"

        check {
          name     = "alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
