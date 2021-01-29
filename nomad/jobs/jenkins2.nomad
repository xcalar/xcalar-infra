job "jenkins2" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"
  priority    = 50

  constraint {
    distinct_hosts = true
  }

  update {
    stagger      = "10s"
    max_parallel = 1
  }

  group "jenkins-master" {
    count = 1

    restart {
      attempts = 10
      interval = "5m"
      delay    = "25s"
      mode     = "delay"
    }

    task "jenkins-master" {
      driver = "docker"

      config {
        image = "jenkins/jenkins:lts-slim"

        force_pull = true

        port_map {
          http = 8080
          jnlp = 50000
          ssh  = 22022
        }

        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock",
          "/netstore/infra/${NOMAD_JOB_NAME}:/var/jenkins_home",
        ]
      }

      service {
        name = "${NOMAD_JOB_NAME}"
        port = "http"

        tags = [
          "http",
          "urlprefix-${NOMAD_JOB_NAME}.service.consul:9999/",
          "urlprefix-${NOMAD_JOB_NAME}.nomad:9999/",
          "urlprefix-${NOMAD_JOB_NAME}.service.consul:443/",
          "urlprefix-${NOMAD_JOB_NAME}.int.xcalar.com:443/",
          "urlprefix-${NOMAD_JOB_NAME}.int.xcalar.com:9999/",
        ]

        check {
          name     = "http port is alive"
          type     = "tcp"
          interval = "20s"
          timeout  = "5s"
        }
      }

      service {
        name = "${NOMAD_JOB_NAME}-ssh"
        port = "ssh"

        tags = ["ssh", "urlprefix-${NOMAD_JOB_NAME}-ssh:22022/ proto=tcp"]

        check {
          name     = "alive"
          type     = "tcp"
          interval = "30s"
          timeout  = "5s"
        }
      }

      service {
        name = "${NOMAD_JOB_NAME}-jnlp"
        port = "jnlp"

        tags = ["jnlp"] #, "urlprefix-:22022 proto=tcp"]

        check {
          name     = "alive"
          type     = "tcp"
          interval = "30s"
          timeout  = "5s"
        }
      }

      resources {
        cpu    = 4000
        memory = 2000

        network {
          port "http" {}

          port "jnlp" {
            static = 50000
          }

          port "ssh" {
            static = 22022
          }
        }
      }

      logs {
        max_file_size = 15
      }

      kill_timeout = "120s"
    }
  }
}
