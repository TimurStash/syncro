.PHONY: tests vendor js js-min watch

#=====================================================================
# Tests

MOCHA = node_modules/.bin/mocha --compilers coffee:coffee-script
OPTS = 
CSOPTS = 

spec:
	$(MOCHA) -R spec tests/*.coffee

dot:
	$(MOCHA) tests/*.coffee

test:
	$(MOCHA) -R spec tests/add.coffee

#=====================================================================
# Build

FILES = src/Base src/BaseList src/models src/sync vendor/ObjectId
VFILES = vendor/backbone.js vendor/jquery.cookie.js vendor/async.js vendor/moment.js vendor/persistence.js vendor/persistence.store.sql.js vendor/persistence.store.websql.js vendor/socket.io.js

js:
	coffee $(CSOPTS) build/build.coffee > lib/client-min.js

server-js:
	coffee $(CSOPTS) -c -o lib src/syncro.coffee src/api.coffee src/apns.coffee
	coffee $(CSOPTS) -c -o lib/storage src/storage/mongodb.coffee 

js-min:
	make js CSOPTS=--minify		

compile:
	@echo "Compiling: Server Files"
	time make server-js
	@echo -n "\nCompiling: Client Files\n"
	time make js

watch:
	watch -n 2 make -s compile

vendor:
	cat $(VFILES) | uglifyjs > lib/vendor.js

w2:
	coffee -wjp $(FILES) > lib/client-min.js
	
