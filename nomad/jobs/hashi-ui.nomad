job "hashi-ui" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"

  group "hashi-ui" {
    count = 1

    task "hashi-ui" {
      driver = "docker"

      config {
        image      = "jippi/hashi-ui"
        force_pull = true

        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock",
        ]

        port_map {
          http = 3000
        }
      }

      env {
        CONSUL_ENABLE          = "1"
        CONSUL_ADDR            = "consul.service.consul:8500"
        CONSUL_HTTP_SSL_VERIFY = "false"

        NOMAD_ENABLE = "1"
        NOMAD_ADDR   = "http://nomad.service.consul:4646"
      }

      resources {
        memory = 500
        cpu    = 1000

        network {
          port "http" {}
        }
      }

      service {
        name = "hashi-ui"

        tags = [
          "urlprefix-hashi-ui.service.consul:9999/",
          "urlprefix-hashi-ui.service.consul:443/",
          "urlprefix-hashi-ui.nomad:9999/",
          "urlprefix-hashi-ui.int.xcalar.com:443/",
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
