.PHONY: tests

#=====================================================================
# Tests

MOCHA = mocha --compilers coffee:coffee-script
OPTS = 
CSOPTS = 

spec:
	$(MOCHA) -R spec tests/*.coffee

dot:
	$(MOCHA) tests/*.coffee

api:
	$(MOCHA) -R spec tests/add.coffee

#=====================================================================
# Build

js:
	coffee build/build.coffee $(CSOPTS) > lib/client-min.js

js-min:
	make js CSOPTS=--minify		

