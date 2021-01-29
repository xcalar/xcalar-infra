job "mssql" {
  datacenters = ["xcalar-sjc"]
  type        = "service"

  constraint {
    attribute = "${meta.cluster}"
    value     = "newton"
  }

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
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    ephemeral_disk {
      sticky  = true
      migrate = true
      size    = 300
    }

    task "mssql" {
      driver = "docker"

      config {
        image = "microsoft/mssql-server-linux"

        port_map {
          db = 1433
        }
      }

      env {
        PATH              = "/opt/mssql-tools/bin:/usr/local/sbin:/usr/sbin:/sbin:/usr/local/bin:/usr/bin:/bin"
        MSSQL_HOST        = "mssql"
        MSSQL_USER        = "sa"
        SA_PASSWORD       = "Password10@"
        MSSQL_SA_PASSWORD = "Password10@"
        ACCEPT_EULA       = "Y"
      }

      resources {
        cpu    = 2000 # 500 MHz
        memory = 1200 # 256MB

        network {
          #mbits = 10
          port "db" {}
        }
      }

      service {
        name = "mssqldb"
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
  }
}
