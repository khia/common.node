APP=$(shell ls src/*.app.src | sed -e 's/src\///g' | sed -e 's/.app.src//g')
NODE=$(subst .,_,$(APP))

all: compile

rebar:
	wget http://hg.basho.com/rebar/downloads/rebar
	chmod u+x rebar

deps: rebar
	./rebar get-deps

compile: deps
	echo $(NODE)
	./rebar compile

release: compile
	rm -rf rel
	mkdir rel ; cd rel ; ../rebar create-node nodeid=$(NODE)
	cd ..
	cp reltool.config rel/
	mkdir -p rel/apps/$(APP)
	cp -R ebin rel/apps/$(APP)
	./rebar generate
	rm -rf rel/apps

console: release
	sh rel/$(NODE)/bin/$(NODE) console

clean:
	./rebar clean