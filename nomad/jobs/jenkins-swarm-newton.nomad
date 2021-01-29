job "jenkins-swarm-raw_exec" {
  datacenters = ["xcalar-sjc"]
  type        = "service"

  constraint {
    attribute = "${meta.name}"
    value     = "newton1"
  }

  constraint {
    distinct_hosts = true
  }

  group "jenkins_swarm" {
    count = 1

    restart {
      attempts = 3
      interval = "5m"
      delay    = "15s"
      mode     = "fail"
    }

    ephemeral_disk {
      sticky  = true
      migrate = false
    }

    task "worker" {
      driver = "raw_exec"

      vault {
        policies = ["jenkins_slave"]
      }

      resources {
        cpu    = 8000  # MHz
        memory = 16048 # MB
      }

      user = "jenkins"

      config {
        command = "/usr/bin/java"

        args = [
          "-Xmx1024m",
          "-Xms256m",
          "-jar",
          "local/swarm-client-3.14.jar",
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
          "-deleteExistingClients",
          "-fsroot",
          "${NOMAD_TASK_DIR}",
        ]
      }

      env {
        "SWARM_PASS" = "D7XmxQFAmqiN66vQtnmz6+bt"
        "SWARM_TAGS" = "nomad debug"
      }

      # Specifying an artifact is required with the "java" driver. This is the
      # mechanism to ship the Jar to be run.
      artifact {
        source = "https://storage.googleapis.com/repo.xcalar.net/deps/swarm-client-3.14.jar"

        options {
          checksum = "sha256:d3bdef93feda423b4271e6b03cd018d1d26a45e3c2527d631828223a5e5a21fc"
        }
      }
    }
  }
}
