express = require 'express'
assets = require 'connect-assets'
path = require 'path'
RedisStore = require('connect-redis')(express)
Log = require('coloured-log')

logger = new Log(Log.Debug)

dbname = 'todos'
port = 8150

app = express.createServer()

redis = new RedisStore

app.configure ->
	app.use express.cookieParser()
	app.use assets
		src: __dirname
	app.use express.bodyParser()
	app.use express.methodOverride()
	app.use express.session
		store: redis
		secret: 'secretkey'
	app.use app.router
	app.set 'views', __dirname
	app.set "jsonp callback", true
	app.use express.errorHandler
		dumpExceptions: true
		showStack: true

syncro = require __dirname + '/../../syncro'

# FIXME: this is a hack
logger.warn = logger.warning

syncro.setLogger logger

# Connect to the Mongo database via Mongoose
syncro.db.connect 'mongodb://localhost/' + dbname

# Include the database schema
dbschema = require './schema'

# Generate the Mongoose schema, models, and socket.io API
syncro.genapi app, dbschema, redis

app.get '/', (req, res) ->
	res.render 'index.jade', { layout: false }

app.listen port

logger.info 'Using database: ' + dbname
logger.info 'Server running at http://127.0.0.1:' + port

