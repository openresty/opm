pidfile = $(abspath web/logs/nginx.pid)
webpath = $(abspath web/)
openresty = openresty
opm = $(abspath bin/opm) --cwd
opm_pkg_indexer = $(abspath util/opm-pkg-indexer.pl) -i 1
tt2_files := $(sort $(wildcard web/templates/*.tt2))
templates_lua = web/lua/opmserver/templates.lua

.DELETE_ON_ERRORS: $(templates_lua)

.PHONY: all
all: $(templates_lua)

$(templates_lua): $(tt2_files)
	mkdir -p web/lua/opmserver/
	lemplate --compile $^ > $@

.PHONY: test
test: | initdb restart
	#./bin/opm build
	#-time ./bin/opm upload
	rm -rf /tmp/final /tmp/failed /tmp/original *.pid
	mkdir -p /tmp/incoming /tmp/final /tmp/failed
	cd ../lua-resty-lrucache && $(opm) build
	cd ../lua-resty-lrucache && $(opm) upload
	PATH=$$PWD/bin:$$PATH time $(opm_pkg_indexer)
	$(opm) get openresty/lua-resty-lrucache
	cd ../lua-resty-core && $(opm) build
	cd ../lua-resty-core && $(opm) upload
	PATH=$$PWD/bin:$$PATH time $(opm_pkg_indexer)
	$(opm) remove openresty/lua-resty-lrucache
	$(opm) get openresty/lua-resty-core
	curl -H 'Server: opm.openresyt.org' http://localhost:8080/

.PHONY: restart
	$(MAKE) stop start

.PHONY: run
run: all
	mkdir -p $(webpath)/logs
	cd web && $(openresty) -p $$PWD/

.PHONY: reload
reload: all
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
