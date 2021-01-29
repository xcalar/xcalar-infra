job "jira-trial" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"
  priority    = 50

  constraint {
    distinct_hosts = true
  }

  group "jira" {
    count = 1

    task "jira-software" {
      driver = "docker"

      config {
        image = "cptactionhank/atlassian-jira-software:latest"

        port_map {
          http = 8080
        }

        volumes = [
          "/netstore/infra/jira:/var/atlassian/jira",
        ]
      }

      env {
        CATALINA_OPTS = "-Xms8g -Xmx16g"
      }

      service {
        name = "jira"
        port = "http"

        tags = ["urlprefix-jira.nomad:9999/", "webapp"]

        check {
          name     = "alive"
          type     = "tcp"
          interval = "60s"
          timeout  = "5s"
        }
      }

      resources {
        cpu    = 8000
        memory = 16000

        network {
          port "http" {}
        }
      }

      logs {
        max_file_size = 15
      }

      kill_timeout = "120s"
    }
  }
}
