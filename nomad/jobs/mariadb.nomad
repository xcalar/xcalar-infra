job "mariadb" {
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

  group "sql" {
    count = 1

    restart {
      attempts = 10
      interval = "5m"
      delay    = "15s"
      mode     = "fail"
    }

    ephemeral_disk {
      sticky  = true
      migrate = true
      size    = 300
    }

    task "mysql" {
      driver = "docker"

      config {
        image = "mariadb:5.5"

        volumes = [
          "/netstore/infra/mariadb:/var/lib/mysql",
        ]

        port_map {
          db = 3306
        }
      }

      env {
        MYSQL_PASSWORD      = "xcalar"
        MYSQL_ROOT_PASSWORD = "xcalar"
      }

      resources {
        cpu    = 500
        memory = 256

        network {
          port "db" {}
        }
      }

      service {
        name = "mysql"
        tags = ["global", "sql"]
        port = "db"

        check {
          name     = "alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }

    ###
    task "myadmin" {
      driver = "docker"

      config {
        image = "phpmyadmin/phpmyadmin:latest"

        port_map {
          ui = 80
        }
      }

      env {
        MYSQL_PASSWORD      = "xcalar"
        MYSQL_ROOT_PASSWORD = "xcalar"
        PMA_ARBITRARY       = 1
        PMA_HOST            = "{{env NOMAD_IP_db }}"
        PMA_PORT            = "{{env NOMAD_PORT_db }}"
      }

      resources {
        cpu    = 500
        memory = 256

        network {
          port "ui" {}
        }
      }

      service {
        name = "myadmin"
        tags = ["urlprefix-myadmin.service.consul:443/"]
        port = "ui"

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
