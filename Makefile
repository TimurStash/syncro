.PHONY: tests

MOCHA = mocha --compilers coffee:coffee-script
OPTS = 

spec:
	$(MOCHA) -R spec tests/*.coffee

dot:
	$(MOCHA) tests/*.coffee

api:
	$(MOCHA) -R spec tests/add.coffee

