pidfile = $(abspath web/logs/nginx.pid)
webpath = $(abspath web/)
openresty = openresty
opm = $(abspath bin/opm) --cwd
opm_pkg_indexer = $(abspath util/opm-pkg-indexer.pl) -i 1
tt2_files := $(sort $(wildcard web/templates/*.tt2))
templates_lua = web/lua/opmserver/templates.lua
md2html = ./util/fmtMd.js
md_files := $(wildcard web/docs/md/*.md)
html_files := $(patsubst web/docs/md/%.md,web/docs/html/%.html,$(md_files))

INSTALL ?= install
CP ?= cp

VERSION ?= 0.1
RELEASE ?= 1

.PRECIOUS: $(md_files)
.DELETE_ON_ERRORS: $(templates_lua)

.PHONY: all
all: $(templates_lua) $(html_files)

$(templates_lua): $(tt2_files)
	mkdir -p web/lua/opmserver/
	lemplate --compile $^ > $@

.PHONY: html
html: $(html_files)

web/docs/html/%.html: web/docs/md/%.md
	@mkdir -p web/docs/html
	$(md2html) $< > $@

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

.PHONY: check
check: clean
	find . -name "*.lua" | lj-releng -L

.PHONY: initdb
initdb: $(tsv_files)
	psql -Uopm opm -f init.sql

.PHONY: install
install:
	$(MAKE) all
	$(INSTALL) -d $(DESTDIR)
	$(INSTALL) -d $(DESTDIR)web/
	$(CP) -r bin $(DESTDIR)bin
	$(CP) -r util $(DESTDIR)util
	$(CP) -r web/conf $(DESTDIR)web/conf
	rm -f $(DESTDIR)web/conf/config.ini
	$(CP) -r web/css $(DESTDIR)web/css
	$(CP) -r web/js $(DESTDIR)web/js
	$(CP) -r web/images $(DESTDIR)web/images
	$(CP) -r web/docs/ $(DESTDIR)web/docs/
	$(CP) -r web/lua $(DESTDIR)web/lua

.PHONY: rpm
rpm:
	rm -rf buildroot
	$(MAKE) install DESTDIR=$$PWD/buildroot/usr/local/opm/
	fpm -f -s dir -t rpm -v "$(VERSION)" --iteration "$(RELEASE)" \
		-n opm-server \
		-C $$PWD/buildroot/ -p ./buildroot \
		--vendor "OpenResty.org" --license Proprietary \
		--description 'opm server' --url 'https://www.openresty.org/' \
		-m 'OpenResty <admin@openresty.org>' \
		--license proprietary -a all \
		usr/local/opm

.PHONY: clean
clean:
	rm -f $(webpath)/lua/opmserver/templates.lua
	rm -f $(html_files)
