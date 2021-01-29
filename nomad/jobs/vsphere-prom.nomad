job "vsphere-prom" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"

  group "vsphere-prom" {
    count = 1

    restart {
      attempts = 5
      interval = "2m"
      delay    = "15s"
      mode     = "fail"
    }

    task "vsphere-prom" {
      driver = "docker"

      config {
        image = "registry.int.xcalar.com/cblomart/vsphere-prom:v20200409"

        volumes = [
          "secrets/vsphere-prom.json:/etc/vsphere-graphite.json",
        ]

        port_map {
          scrape = 9155
        }
      }

      resources {
        memory = 512
        cpu    = 1000

        network {
          port "scrape" {
            static = "9155"
          }
        }
      }

      service {
        name = "vsphere-exporter"
        port = "scrape"
        tags = ["vsphere-prom.nomad:9999/", "urlprefix-vsphere-exporter.service.consul:9999/", "prometheus"]

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
{{ with secret "secret/data/infra/vsphere-prom" }}{{ .Data.data.data }}{{ end }}
EOT

        destination = "secrets/vsphere-prom.json"
      }
    }
  }
}
