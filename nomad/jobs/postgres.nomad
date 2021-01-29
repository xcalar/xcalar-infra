job "postgres" {
  datacenters = ["xcalar-sjc"]
  type        = "service"

  constraint {
    attribute = "${meta.cluster}"
    value     = "newton"
  }

  group "postgres" {
    count = 1

    ephemeral_disk {
      sticky  = true
      migrate = true
      size    = 300
    }

    task "postgres" {
      driver = "docker"

      config {
        image = "postgres:9.6"

        port_map {
          db = 5432
        }
      }

      vault {
        policies = ["jenkins_slave"]
      }

      template {
        data = <<EOT
{{ with secret "secret/data/roles/jenkins-slave/postgres" }}
POSTGRES_PASSWORD={{ .Data.data.password }}
POSTGRES_USER={{ .Data.data.user }}
POSTGRES_DB={{ .Data.data.db }}{{ end }}
EOT

        destination = "secrets/postgres.env"
        env         = true
      }

      resources {
        cpu    = 2000 # 500 MHz
        memory = 1200 # 256MB

        network {
          port "db" {}
        }
      }

      service {
        name = "postgres"
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
