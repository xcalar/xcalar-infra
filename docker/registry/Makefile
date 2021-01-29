
default: network volumes
	docker-compose up -d

network:
	cd $(XLRDIR)/docker/xcalarnet && make

volumes:
	docker volume create redis
	docker volume create registry
	docker volume create postgres
