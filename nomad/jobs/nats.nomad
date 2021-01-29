job "nats" {
  datacenters = ["xcalar-sjc"]
  type        = "service"

  update {
    stagger      = "10s"
    max_parallel = 1
  }

  group "nats" {
    count = 1

    restart {
      attempts = 10
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }

    task "nats_streaming_server" {
      driver = "docker"

      config {
        image      = "nats-streaming:latest"
        force_pull = true

        port_map {
          nats_streaming_port = 4222
          streaming_ui_port   = 8222
        }

        #        args = [
        #          "--client_advertise",
        #          "${NOMAD_IP_io}",
        #          "--http_port",
        #          "${NOMAD_PORT_web_port}",
        #          "-c",
        #          "nats-server.conf",
        #        ]
      }

      resources {
        cpu    = 500
        memory = 128

        network {
          port "nats_streaming_port" {}

          port "streaming_ui_port" {}
        }
      }

      service {
        name = "nats-streaming"
        tags = ["nats-streaming"]
        port = "nats_streaming_port"

        check {
          name     = "nats_streaming_port is alive"
          type     = "tcp"
          interval = "20s"
          timeout  = "8s"
        }
      }

      service {
        name = "nats-streaming-ui"
        tags = ["urlprefix-nats-streaming-ui.service.consul:9999/", "urlprefix-nats-streaming-ui.service.consul:443/"]
        port = "streaming_ui_port"

        check {
          name     = "streaming_ui_port alive"
          type     = "http"
          path     = "/varz"
          interval = "20s"
          timeout  = "5s"
        }
      }
    }

    task "nats_server" {
      driver = "docker"

      config {
        image      = "nats:2"
        force_pull = true

        port_map {
          nats_port  = 4222
          route_port = 6222
          ui_port    = 8222
        }

        #        args = [
        #          "--client_advertise",
        #          "${NOMAD_IP_io}",
        #          "--http_port",
        #          "${NOMAD_PORT_web_port}",
        #          "-c",
        #          "nats-server.conf",
        #        ]
      }

      resources {
        cpu    = 500
        memory = 128

        network {
          port "nats_port" {
            static = "4222"
          }

          port "route_port" {
            static = "6222"
          }

          port "ui_port" {
            static = "8222"
          }
        }
      }

      service {
        name = "nats"
        tags = ["nats"]
        port = "nats_port"

        check {
          name     = "nats_port is alive"
          type     = "tcp"
          interval = "20s"
          timeout  = "8s"
        }
      }

      service {
        name = "nats-route"
        tags = ["nats-route"]
        port = "route_port"

        check {
          name     = "route_port is alive"
          type     = "tcp"
          interval = "20s"
          timeout  = "8s"
        }
      }

      service {
        name = "nats-ui"
        tags = ["urlprefix-nats-ui.service.consul:9999/"]
        tags = ["urlprefix-nats-ui.service.consul:443/"]
        port = "ui_port"

        check {
          name     = "ui_port alive"
          type     = "http"
          path     = "/varz"
          interval = "20s"
          timeout  = "5s"
        }
      }
    }
  }
}
