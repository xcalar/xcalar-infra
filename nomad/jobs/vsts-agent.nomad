job "vsts" {
  datacenters = ["xcalar-sjc"]

  group "vsts" {
    count = 1

    restart {
      attempts = 5
      interval = "2m"
      delay    = "15s"
      mode     = "fail"
    }

    reschedule {
      attempts       = 15
      interval       = "1h"
      delay          = "30s"
      delay_function = "exponential"
      max_delay      = "120s"
      unlimited      = false
    }

    constraint {
      distinct_hosts = true
    }

    constraint {
      attribute    = "${meta.cluster}"
      set_contains = "newton"
    }

    task "agent" {
      driver = "docker"

      config {
        image = "registry.int.xcalar.com/xcalar/el7-vsts-agent:v1"

        volumes = [
          "/var/run/docker.sock:/var/run/docker.sock",
          "/netstore:/netstore",
        ]
      }

      vault {
        policies = ["jenkins_slave"]
        env      = true
      }

      env {
        VAULT_ADDR = "https://vault.service.consul:8200"
      }

      template {
        data = <<EOT
        {{ with secret "secret/data/infra/vsts" }}
        AZP_URL        = "https://dev.azure.com/xcalar"
        AZP_TOKEN      = "{{ .Data.data.token }}"
        AZP_AGENT_NAME = "mydockeragent"
        DOCKER_HOST    = "unix:///var/run/docker.sock"{{ end }}
EOT

        env         = true
        destination = "secrets/vsts.env"
      }

      resources {
        memory = 4096
        cpu    = 8000
      }
    }
  }
}

# resources {
#   memory = 500
#   network {
#     port "ipc" {
#       static = "8020"
#     }
#     port "ui" {
#       static = "50070"
#     }
#   }
# }
# service {
#   name = "hdfs"
#   port = "ipc"
# }
# config {
#   command = "bash"
#   args = [ "-c", "hdfs namenode -format && exec hdfs namenode -D fs.defaultFS=hdfs://${NOMAD_ADDR_ipc}/ -D dfs.permissions.enabled=false" ]
#   network_mode = "host"
#   port_map {
#     ipc = 8020
#     ui = 50070
#   }
# }

