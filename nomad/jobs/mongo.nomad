job "mongo" {
  datacenters = ["xcalar-sjc"]
  type        = "service"

  update {
    stagger      = "10s"
    max_parallel = 1
  }

  group "db_m" {
    count = 1

    restart {
      attempts = 10
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }

    ephemeral_disk {
      size = 300
    }

    task "mongo" {
      driver = "docker"

      config {
        image = "mongo"

        port_map {
          db = 27017
        }

        volumes = [
          "/netstore/infra/mongodb:/data/db",
        ]
      }

      env {
        MONGO_INITDB_ROOT_USERNAME = "root"
        MONGO_INITDB_ROOT_PASSWORD = "Welcome1"
      }

      resources {
        cpu    = 1500 # Mhz
        memory = 2048 # MB

        network {
          port "db" {
            static = "27017"
          }
        }
      }

      service {
        name = "mongodb"
        tags = ["db"]
        port = "db"

        check {
          name     = "alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "4s"
        }
      }
    }

    task "adminmongo" {
      driver = "docker"

      config {
        image        = "mrvautin/adminmongo"
        network_mode = "host"

        port_map {
          ui = 1234
        }
      }

      env {
        CONN_NAME   = "local"
        DB_USERNAME = "root"
        DB_PASSWORD = "Welcome1"
        DB_HOST     = "${NOMAD_IP_db}"
        DB_PORT     = "${NOMAD_PORT_db}"
        HOST        = "0.0.0.0"
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 1024 # 256MB

        network {
          port "ui" {
            static = "1234"
          }
        }
      }

      service {
        name = "adminmongo"
        tags = ["urlprefix-adminmongo.service.consul:443/"]
        port = "ui"

        check {
          name     = "alive"
          type     = "tcp"
          interval = "10s"
          timeout  = "4s"
        }
      }
    }
  }
}
