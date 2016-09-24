pidfile = $(abspath web/logs/nginx.pid)
webpath = $(abspath web/)
openresty = openresty
opm = $(abspath bin/opm)
opm_pkg_indexer = $(abspath util/opm-pkg-indexer.pl)

.PHONY: test
test: | initdb reload
	#./bin/opm build
	#-time ./bin/opm upload
	rm -rf /tmp/final /tmp/failed /tmp/original
	mkdir -p /tmp/incoming /tmp/final /tmp/failed
	cd ../lua-resty-lrucache && $(opm) build
	cd ../lua-resty-lrucache && $(opm) upload
	cd ../lua-resty-core && $(opm) build
	cd ../lua-resty-core && $(opm) upload
	PATH=$$PWD/bin:$$PATH time $(opm_pkg_indexer)
	$(opm) --cwd get openresty/lua-resty-core

.PHONY: run
run:
	mkdir -p $(webpath)/logs
	cd web && $(openresty) -p $$PWD/

.PHONY: reload
reload:
	$(openresty) -p $(webpath)/ -t
	test -f $(pidfile)
	rm -f $(webpath)/logs/error.log
	#rm -f /tmp/openresty/*
	#kill -USR1 `cat $(pidfile)`
	kill -HUP `cat $(pidfile)`
	sleep 0.002

.PHONY: stop
stop:
	test -f $(pidfile)
	kill -QUIT `cat $(pidfile)`

.PHONY: restart
restart:
	-$(MAKE) stop
	sleep 0.01
	$(MAKE) run

.PHONY: clean
clean:
	rm -f $(webpath)/logs/*

.PHONY: initdb
initdb: $(tsv_files)
	psql -Uopm opm -f init.sql
