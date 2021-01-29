job "elk" {
  datacenters = ["dontrunitsbroken"]
  type        = "service"

  update {
    stagger      = "10s"
    max_parallel = 1
  }

  group "elk-kibana" {
    count = 1

    task "kibana" {
      driver = "docker"

      config {
        image = "amazon/opendistro-for-elasticsearch-kibana:1.0.2"

        logging {
          type = "json-file"
        }

        port_map {
          ui_port = 5601
        }

        #        volumes = [
        #          "local/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml",
        #        ]
      }

      resources {
        cpu    = 2000
        memory = 2000

        network {
          port "ui_port" {}
        }
      }

      service {
        name = "kibana"
        tags = ["urlprefix-kibana.service.consul:443/"]
        port = "ui_port"

        check {
          type     = "http"
          path     = "/"
          port     = "ui_port"
          interval = "20s"
          timeout  = "5s"
        }
      }

      env {
        ELASTICSEARCH_URL   = "https://elasticsearch.service.consul"
        ELASTICSEARCH_HOSTS = "https://elasticsearch.service.consul:9200"
      }

      #      template {
      #        destination = "local/elasticsearch.yml"
      #      }
    }
  }

  group "es" {
    count = 3

    ephemeral_disk {
      sticky  = true
      migrate = true
      size    = 2000
    }

    task "elasticsearch" {
      driver = "docker"

      config {
        image = "amazon/opendistro-for-elasticsearch:1.0.2"

        ulimit {
          nofile  = "65536"
          memlock = "-1"
          nproc   = "65536"
        }

        logging {
          type = "json-file"

          config {
            max-file = 10
            max-size = "100m"
          }
        }

        network_mode = "host"

        port_map {
          es_rest = 9200
          es_ui   = 9600
        }

        volumes = [
          "local/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml",
          "local/data:/usr/share/elasticsearch/data",
        ]
      }

      resources {
        cpu    = 4000
        memory = 4000

        network {
          port "es_rest" {
            static = "9200"
          }

          port "es_ui" {
            static = "9600"
          }
        }
      }

      service {
        name = "elasticsearch"

        tags = ["elastic", "urlprefix-elasticsearch.service.consul:443/"]

        port = "es_rest"

        check {
          name     = "es_rest port check"
          type     = "http"
          path     = "/"
          port     = "es_rest"
          interval = "10s"
          timeout  = "2s"
        }
      }

      env {
        ES_JAVA_OPTS          = "-Xms${NOMAD_MEMORY_LIMIT}m -Xmx${NOMAD_MEMORY_LIMIT}m"
        bootstrap.memory_lock = "true"
        node.name             = "${NOMAD_JOB_NAME}-${NOMAD_TASK_NAME}-${NOMAD_ALLOC_INDEX}"
      }

      template {
        destination = "local/elasticsearch.yml"

        data = <<EOT
cluster.name: {{ env "NOMAD_JOB" }}
node.name: {{ env "NOMAD_JOB_NAME" }}-{{ env "NOMAD_TASK_NAME" }}-{{ env "NOMAD_ALLOC_INDEX" }}
network.host: {{ env "NOMAD_IP_es_rest" }}
cluster.initial_master_nodes: {{ env "NOMAD_JOB_NAME" }}-{{ env "NOMAD_TASK_NAME" }}-0,{{ env "NOMAD_JOB_NAME" }}-{{ env "NOMAD_TASK_NAME" }}-1,{{ env "NOMAD_JOB_NAME" }}-{{ env "NOMAD_TASK_NAME" }}-2
discovery.seed_hosts: {{ env "NOMAD_JOB_NAME" }}-{{ env "NOMAD_TASK_NAME" }}-0,{{ env "NOMAD_JOB_NAME" }}-{{ env "NOMAD_TASK_NAME" }}-1,{{ env "NOMAD_JOB_NAME" }}-{{ env "NOMAD_TASK_NAME" }}-2
discovery.zen.minimum_master_nodes: 3
EOT
      }
    }

    # - end elasticsearch - #
  }

  # - end logging-elk - #
}
