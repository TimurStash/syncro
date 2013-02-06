Snockets = require 'snockets'
snockets = new Snockets()
optimist = require('optimist')

argv = optimist
	.alias('m', 'minify')
	.argv

js = snockets.getConcatenation 'src/client.coffee',
	async: false
	minify: argv.m

console.log js
