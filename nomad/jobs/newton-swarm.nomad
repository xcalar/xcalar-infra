job "newton-swarm" {
  datacenters = ["xcalar-sjc"]
  type        = "service"

  constraint {
    attribute    = "${meta.cluster}"
    set_contains = "newton"
  }

  group "jenkins-swarm" {
    count = 2

    constraint {
      distinct_hosts = true
    }

    #    constraint {
    #      attribute = "${node_class}"
    #      operator  = "set_contains"
    #      value     = "jenkins_slave"
    #    }

    restart {
      attempts = 10
      interval = "5m"
      delay    = "15s"
      mode     = "fail"
    }
    ephemeral_disk {
      sticky  = true
      migrate = false
    }
    task "jenkins_slave" {
      driver = "java"

      resources {
        cpu    = 8000 # MHz
        memory = 8000 # MB
      }

      config {
        jar_path    = "local/swarm-client-3.15.jar"
        jvm_options = ["-Xmx512m", "-Xms256m"]

        args = [
          "-master",
          "https://jenkins.int.xcalar.com/",
          "-sslFingerprints",
          "D7:F9:76:25:B2:7D:E9:00:59:00:9B:CD:CE:6B:5F:97:9E:2F:68:A3:79:13:FE:F6:43:9F:A7:D0:5B:AC:7F:78",
          "-executors",
          "2",
          "-labels",
          "${SWARM_TAGS}",
          "-mode",
          "exclusive",
          "-username",
          "swarm",
          "-passwordEnvVariable",
          "SWARM_PASS",
        ]
      }

      env {
        "SWARM_TAGS" = "nomad debug"
      }

      vault {
        policies = ["jenkins_slave"]
        env      = true
      }

      template {
        data = <<EOT
SWARM_PASS={{ with secret "secret/data/roles/jenkins-slave/swarm" }}{{ .Data.data.password }}{{ end }}
EOT

        destination = "secrets/swarm_pass.env"
        env         = true
      }

      # Specifying an artifact is required with the "java" driver. This is the
      # mechanism to ship the Jar to be run.
      artifact {
        source = "https://storage.googleapis.com/repo.xcalar.net/deps/swarm-client-3.15.jar"

        options {
          checksum = "sha256:6812e86a220d2d6c4d3fffabd646b7bb19a4144693958b2a943fa6b845f081b1"
        }
      }
    }
  }
}
