job "gocd" {
  datacenters = ["xcalar-sjc"]
  type        = "service"

  update {
    stagger      = "10s"
    max_parallel = 1
  }

  #  group "gocd_agent" {
  #    count = 1
  #
  #    restart {
  #      attempts = 10
  #      interval = "5m"
  #      delay    = "25s"
  #      mode     = "delay"
  #    }
  #
  #    ephemeral_disk {
  #      size = 300
  #    }
  #
  #    task "gocd_agent" {
  #      driver = "docker"
  #
  #      config {
  #        image = "gocd/gocd-agent-centos-7:v19.12.0"
  #
  #        #args = [ "-e", ]
  #
  #        dns_search_domains = ["int.xcalar.com"]
  #        dns_servers        = ["${NOMAD_IP_cnc}:8600", "10.10.2.136", "10.10.6.32"]
  #        volumes = [
  #          "./local:/godata",
  #          "/var/run/docker.sock:/var/run/docker.sock",
  #        ]
  #      }
  #
  #      template {
  #        env         = true
  #        destination = "secret/gocd.env"
  #
  #        data = <<EOT
  #GO_SERVER_URL="https://gocd.service.consul/go"
  #EOT
  #      }
  #
  #      resources {
  #        cpu    = 1000
  #        memory = 1000
  #
  #        network {
  #          port "cnc" {}
  #        }
  #      }
  #
  #      env {
  #        "GOCD_PLUGIN_INSTALL_docker-elastic-agents" = "https://github.com/gocd-contrib/docker-elastic-agents/releases/download/v3.0.0-222/docker-elastic-agents-3.0.0-222.jar"
  #        "GO_SERVER_URL"                             = "https://gocd.service.consul/go"
  #      }
  #    }
  #  }

  group "gocd" {
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

    task "gocd_server" {
      driver = "docker"

      config {
        image = "gocd/gocd-server:v20.4.0"

        dns_search_domains = ["int.xcalar.com"]
        dns_servers        = ["10.10.2.136", "10.10.6.32"]

        port_map {
          ui = 8153
        }

        volumes = [
          "/netstore/infra/gocd/data:/godata",
          "/netstore/infra/gocd/home:/home/go",
          "/netstore/infra/gocd/go-working-dir:/go-working-dir",
          "/var/run/docker.sock:/var/run/docker.sock",
        ]
      }

      env {
        "GOCD_PLUGIN_INSTALL_docker-elastic-agents" = "https://github.com/gocd-contrib/docker-elastic-agents/releases/download/v3.1.0-248-exp/docker-elastic-agents-3.1.0-248.jar"
        "GOCD_SERVER_JVM_OPTS"                      = "-Xms500m -Xmx2g -Djava.awt.headless=true"
      }

      resources {
        cpu    = 4000
        memory = 3000

        network {
          port "ui" {
            static = "8153"
          }
        }
      }

      service {
        name = "gocd"
        tags = ["urlprefix-gocd.service.consul:443/"]
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
