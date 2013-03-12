# Set up an express server, generate the API on it, and seed the DB

# TODO: use defaults but allow override via CLI
port = 8900
proxyport = 9000
dbname = 'apitest'
host = '127.0.0.1'

# Modules
express = require 'express'
io = require 'socket.io-client'
syncro = require '../src/syncro'
httpProxy = require 'http-proxy'
fixtures = require('pow-mongodb-fixtures').connect(dbname)
id = require('pow-mongodb-fixtures').createObjectId

# Assertions & spies
sinon = require 'sinon'
chai = require 'chai'
should = chai.should()
sinonChai = require 'sinon-chai'
chai.use sinonChai

# FIXME: move this to a file
dbschema =
	schema:
		Student:
			name: String
		User:
			userid:
				type: String
				index: true
				required: true
			token:
				type: String
				index: true
				private: true
	map:
		Student: true

{Db, Connection, Server} = require 'mongodb'

db = {}

exports.fetch = (cname, cb) ->
	db.collection cname, (err, coll) ->
		coll.find().toArray (err, objs) ->
			cb objs

setupDB = (cb) ->
	client = new Db(dbname, new Server(host, Connection.DEFAULT_PORT, {}))
	client.open (err, client) ->
		db = client
		cb()

#server = new mongodb.Server '127.0.0.1', 27017, {}
echo = (msg) -> console.log msg

exports.logger = ->
	log =
		debug: sinon.spy()
		info: sinon.spy()
		notice: sinon.spy()
		warn: sinon.spy()
		error: sinon.spy()
	syncro.setLogger log
	log

# Seed the database with some users
seedDB = (cb) ->
	data =
		users: [
			_id: id("50a8a033e66edd27b0000005")
			name: 'Alice'
			token: 'alice_token'
		]

	fixtures.clearAllAndLoad data, cb

# Start express, generate the API, and attach the socket
startExpress = (cb) ->
	# Proxy server
	httpProxy.createServer (req, res, proxy) ->
		req.headers.cookie = 'token=alice_token;'
		proxy.proxyRequest req, res,
			host: 'localhost',
			port: port
	.listen(proxyport)

	# Start the server
	app = express.createServer()

	syncro.db.connect 'mongodb://localhost/' + dbname


	# Generate the Mongoose schema, models, and socket.io API
	syncro.genapi app, dbschema

	app.listen port, null, null, ->
		#console.log "Server running at http://localhost:#{port}"

		socket = io.connect '127.0.0.1:' + proxyport,
			reconnect: true
			'connect timeout': 10

		socket.on 'connect', (misc) ->
			#console.log "Connected"
			cb()

		socket.on 'error', (err) ->
			#console.log 'Socket.IO error:', err
			false

		exports.emit = (type, data, cb) ->
			socket.emit type, data, cb

# Seed DB and start server
exports.start = (cb) ->
	seedDB ->
		setupDB ->
			startExpress cb



