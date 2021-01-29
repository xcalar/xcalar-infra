job "registryv2" {
  region      = "global"
  datacenters = ["xcalar-sjc"]
  type        = "service"

  update {
    max_parallel      = 1
    min_healthy_time  = "10s"
    healthy_deadline  = "3m"
    progress_deadline = "10m"
    auto_revert       = false
    canary            = 0
  }

  migrate {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }

  group "registry" {
    constraint {
      distinct_hosts = true
    }

    count = 2

    restart {
      attempts = 5
      interval = "5m"
      delay    = "15s"
    }

    task "registry" {
      driver = "docker"

      artifact {
        source = "http://netstore.int.xcalar.com/infra/images/registryv2-202011151431.tar"
      }

      config {
        load  = "registryv2-202011151431.tar"
        image = "registry:2"

        volumes = [
          "/netstore/infra/registry/_data:/var/lib/registry",
          "local/config.yml:/etc/docker/registry/config.yml",
        ]

        port_map {
          image      = 5000
          debug_port = 5001
        }
      }

      resources {
        memory = 500
        cpu    = 1000

        network {
          port "image"{}
          port "debug_port"{}
        }
      }

      service {
        name = "registry"
        port = "image"

        tags = [
          "urlprefix-registry.service.consul:9999/",
          "urlprefix-registry.service.consul:443/",
          "urlprefix-registry.int.xcalar.com:443/",
        ]

        check {
          name     = "image port check"
          type     = "tcp"
          interval = "20s"
          timeout  = "10s"
        }
      }

      service {
        name = "debug"
        port = "debug_port"

        tags = [
          "http",
          "prometheus",
        ]

        check {
          name     = "debug_port check"
          type     = "tcp"
          interval = "10s"
          timeout  = "4s"
        }
      }

      env {
        VAULT_ADDR         = "https://vault.service.consul:8200"
        AWS_DEFAULT_REGION = "us-west-2"
        AWS_REGION         = "us-west-2"
      }

      vault {
        policies    = ["aws", "aws-xcalar", "ca-int-xcalar-com"]
        env         = true
        change_mode = "restart"
      }

      /*
                                                artifact {
                                                  source      = "https://vault.service.consul:8200/v1/xcalar_ca/ca_chain"
                                                  destination = "local/ca.pem"
                                                  mode        = "file"
                                                }

                                                template {
                                                  destination = "local/cert.crt"

                                                  data = <<EOH
                                          {{ with secret "xcalar_ca/issue/int-xcalar-com" "common_name=registry.service.consul" "ttl=24h" }}
                                          {{ .Data.certificate }}
                                          {{ end }}
                                                EOH
                                                }

                                                template {
                                                  destination = "secrets/cert.key"

                                                  data = <<EOH
                                          {{ with secret "xcalar_ca/issue/int-xcalar-com" "common_name=registry.service.consul" "ttl=24h" }}
                                          {{ .Data.private_key }}
                                          {{ end }}
                                                EOH
                                                }

                                                template {
                                                  data = <<EOH
                                                      Good morning.
                                                      <br />
                                                      <br />
                                          {{ with secret "xcalar_ca/issue/int-xcalar-com" "common_name=registry.service.consul" "ttl=24h" }}
                                          {{ .Data.certificate }}
                                                      <br />
                                                      <br />
                                          {{ .Data.private_key }}
                                          {{ end }}
                                                  EOH

                                                  destination = "local/index.html"
                                                }

                                                template {
                                                  destination = "secrets/creds.env"
                                                  change_mode = "restart"
                                                  env         = true

                                                  data = <<EOT
                                          {{ with secret "aws-xcalar/sts/xcnexus" "ttl=86400"}}
                                          AWS_ACCESS_KEY_ID={{ .Data.access_key }}
                                          AWS_SECRET_ACCESS_KEY={{ .Data.secret_key }}
                                          AWS_SESSION_TOKEN={{ .Data.security_token }}{{ end }}
                                          EOT
                                                }
                                          */
      template {
        destination = "local/config.yml"
        change_mode = "restart"

        data = <<EOD
version: 0.1
log:
  level: "debug"
  formatter: "json"
  fields:
    service: "registry"
storage:
  cache:
    blobdescriptor: redis
  filesystem:
    rootdirectory: /var/lib/registry
  #s3:
  #  region: "us-west-2"
  #  bucket: "xcnexus"
  #  rootdirectory: "registryv2/"
redis:
  addr: {{range $i, $e := service "redis" "any"}}{{$e.Address}}:{{$e.Port}}{{end}}
  db: 15
  dialtimeout: 10ms
  readtimeout: 10ms
  writetimeout: 10ms
  pool:
    maxidle: 16
    maxactive: 64
    idletimeout: 300s
http:
  addr: :5000
  secret: "asekr3t"
  #tls:
  #  certificate: /local/cert.crt
  #  key: /secrets/cert.key
  #  clientcas:
  #    - /local/ca.pem
  debug:
    addr: :5001
    prometheus:
      enabled: true
      path: "/metrics"
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: true
    interval: "10s"
    threshold: 3
EOD
      }
    }
  }
}
