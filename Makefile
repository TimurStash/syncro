.PHONY: tests vendor js js-min watch

#=====================================================================
# Tests

MOCHA = node_modules/.bin/mocha --compilers coffee:coffee-script

spec:
	$(MOCHA) -R spec tests/*.coffee

dot:
	$(MOCHA) tests/*.coffee

test:
	$(MOCHA) -R spec tests/add.coffee tests/edit.coffee

#=====================================================================
# Build

FILES = src/Base src/BaseList src/models src/sync vendor/ObjectId
VFILES = vendor/backbone.js vendor/jquery.cookie.js vendor/async.js vendor/moment.js vendor/persistence.js vendor/persistence.store.sql.js vendor/persistence.store.websql.js vendor/socket.io.js
EXT = 
BLDOPTS = 
CSOPTS = 

build: js js-min server-js

js:
	coffee build/build.coffee $(BLDOPTS) > lib/client$(EXT).js

server-js:
	coffee $(CSOPTS) -c -o lib src/syncro.coffee src/api.coffee src/apns.coffee
	coffee $(CSOPTS) -c -o lib/storage src/storage/mongodb.coffee 

js-min:
	make js BLDOPTS=--minify EXT=-min	

compile:
	@echo "Compiling: Server Files"
	time make server-js
	@echo -n "\nCompiling: Client Files\n"
	time make js

watch:
	watch -n 2 make -s compile
