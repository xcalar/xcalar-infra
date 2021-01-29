job "ovirt-prom" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"

  group "ovirt-prom" {
    count = 1

    restart {
      attempts = 5
      interval = "2m"
      delay    = "15s"
      mode     = "fail"
    }

    task "ovirt-prom" {
      driver = "docker"

      config {
        image = "registry.int.xcalar.com/infra/ovirt-exporter"

        volumes = [
          "secrets/ovirt-prom.env:/etc/ovirt-prom.env",
        ]

        port_map {
          scrape = 9325
        }
      }

      resources {
        memory = 512
        cpu    = 1000

        network {
          port "scrape" {
            static = "9325"
          }
        }
      }

      service {
        name = "ovirt-exporter"
        port = "scrape"
        tags = ["ovirt-prom.nomad:9999/", "urlprefix-ovirt-exporter.service.consul:9999/", "prometheus"]

        check {
          name     = "scrape port alive"
          type     = "tcp"
          interval = "20s"
          timeout  = "10s"
        }
      }

      vault {
        policies = ["jenkins_slave"]
      }

      template {
        data = <<EOT
{{ with secret "secret/data/infra/ovirt-prom" }}{{ .Data.data.data }}{{ end }}
EOT

        destination = "secrets/ovirt-prom.env"
        env         = true
      }
    }
  }
}
