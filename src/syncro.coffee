# TODO: abstract the DB out more so that MySQL, etc. can be used instead of Mongo

socketio = require 'socket.io'
mongoose = require 'mongoose'
cookie = require 'cookie'
async = require 'async'

models = {}

# Default logger: No-op
#logger = {}
noop = ->
logger =
	debug: noop
	info: noop
	warn: noop
	error: noop
	notice: noop

ApiRequest = require './api'

ObjectId = mongoose.Types.ObjectId

setLogger = (mylog) ->
	logger = mylog
	ApiRequest.setLogger logger

# TODO: add ability to map field names on client/server to new names

db = require './storage/mongodb'

# TODO: Specify the User model name in the DB schema somehow, instead of hard-coding it
checkUser = (user, pass, cb) ->
	models['User'].model.findOne { userid: user, password: pass }, (err, myuser) ->
		if myuser
			logger.info "Login: " + user
		else
			logger.warn "Login error: " + user

		cb err, myuser

getUserById = (userid, cb) ->
	models['User'].model.findOne { userid: userid }, (err, myuser) ->
		throw err if err?
		cb null, myuser

getUserByToken = (token, cb) ->
	models['User'].model.findOne { token: token }, (err, myuser) ->
		throw err if err?
		cb null, myuser

cmdErr = (err, cb) ->
	logger.error err
	# TODO: send something back using socket.io
	cb false if cb



applyMixins = (dbschema) ->
	for fname,val of dbschema.mixins
		for mname in val.models
			schema = dbschema.schema[mname]

			if val.peruser
				schema[fname] =
					type: [ObjectId]
					peruser: true
			else
				schema[fname] =
					type: val.type

# FIXME: move to API file
listUsers = (cb) ->
	models.User.model.find cb

listObjs = (type, cb) ->
	unless models[type]
		return cb "Model type '#{type}' does not exist in schema"

	models[type].model.find cb 

dbinit = (dbschema, logger) ->
	models = db.genschema dbschema, logger
	ApiRequest.setData dbschema, models, logger

addObj = (type, props, cb) ->
	unless models[type]
		return cb "Model type '#{type}' does not exist in schema"

	logger.debug "Creating new #{type}"

	api = new ApiRequest
	api.cmdErr = (err) ->
		cb err
	api.cb = cb

	changes = {}
	for key, val of props
		changes[key] = val

	# Create the history array and push the changes object on to it
	props.history = []
	props.history.push
		changes: changes

	obj = api.addObject type, props

addUser = (props, cb) ->
	addObj 'User', props, cb

addPerm = (userid, type, props, cb) ->
	unless models[type]
		return cb "Model type '#{type}' does not exist in schema"

	# Fetch the user
	models.User.model.findOne { userid: userid }, (err, user) ->
		return cb "Could not get user: #{userid}" if err? or not user

		# Get the object to grant permissions on
		models[type].model.findOne props, (err, obj) ->
			return cb "Could not find '#{type}' object" if err?
	
			#console.log user, obj

			# Create the Right object & save it
			perm = new models.Right.model
				user: user._id
				objid: obj._id
				access: "full"
				type: type

			perm.save (err) ->
				return cb err


# FIXME: rewrite this to use classes or closures better so there is less argument passing
#console.log '## Model: ' + mname
genapi = (app, dbschema) ->

	applyMixins dbschema

	models = db.genschema dbschema, logger

	ApiRequest.setData dbschema, models, logger

	# Attach socket.io to the Express application
	io = socketio.listen app
	io.set 'log level', 1

	# Authorization
	io.configure () ->
		io.set 'authorization', (data, cb) ->
			if data.headers.cookie
				data.cookie = cookie.parse data.headers.cookie

				if data.cookie.token
					getUserByToken data.cookie.token, (err, user) ->
						if user
							logger.info 'Socket.IO user: ' + user.userid
							# Save the User object and ID on to the handshake data
							data.user = user
							data.userid = user.userid
							cb null, true
						else
							logger.warn 'Socket.IO: Invalid token: ' + data.cookie.token
							cb 'Invalid token', false

				else
					logger.error 'Socket.IO: No token'
					cb 'No token', false
			else
				logger.error 'Socket.IO: No cookie'
				cb 'No cookie transmitted.', false

	# Generate the socket.io API
	io.sockets.on 'connection', (socket) ->
		logger.info 'Socket.IO connection: ' + socket.id

		user = socket.handshake.user
		socket.emit 'auth',
			username: user.userid
			id: user._id

		# Join all sockets to a room named by the user ID
		socket.join user._id

		socket.on 'sync', (objs, cb) ->
			logger.notice 'Sync: ' + socket.id
			#console.log objs
			cb()

			new ApiRequest(socket).syncObjects(objs)

		# Save Apple Push Notifications for users
		socket.on 'apntoken', (data, cb) ->
			user = socket.handshake.user
			token = new db.ApnToken
				user: user._id
				value: data

			token.save (err) ->
				return cmdErr 'Could not save APN Token: ' + user.userid + ' : ' + data, cb if err?

				logger.notice "Added APN Token for user: " + user.userid
				cb { ok: true }

		for mname,modelobj of models
			#console.log 'Model:', mname
			continue if mname.match /^(Right|ApnToken)$/

			bindio = ->
				areq = ApiRequest.bind socket, mname

				mobj = modelobj
				model = modelobj.model
				modelname = mname

				socket.on 'add:' + mname, (data, cb) ->

					areq(data, cb).add()

				socket.on 'get:' + mname, (id, cb) ->
					logger.info 'Get: ' + modelname + ' : ' + id
					model.findById id, (err, obj) ->
						cb JSON.stringify(obj)

				socket.on 'list:' + mname, (cb) ->
					logger.info 'List: ' + modelname
					model.find {}, (err, objs) ->
						cb JSON.stringify(objs)

				socket.on 'delete:' + mname, (data, cb) ->
					model.findById data.id

				socket.on 'edit:' + mname, (data, cb) ->

					areq(data, cb).edit()

				socket.on 'find:' + mname, (data, cb) ->
					# Word matching
					condition = {}
					match = []
					if data.words.length
						for word in data.words
							match.push
									$or: [
										{ title:
											$regex: new RegExp(word, 'i') }
										,
										{ description:
											$regex: new RegExp(word, 'i') }
										,
										{ 'events.notes':
											$regex: new RegExp(word, 'i') }
									]
						condition =
							$and: match

					query = model.find condition
					#query.where('project', data.project) if data.project

					# TODO: verify the fields that can be specified
					# Query axis: area, etc.
					for key, val of data.fields
						query.where(key, val)

					#unless data.all
					#	query.where('status', "Active")

					if data.limit
						query.limit(data.limit)

					query.exec (err, objs) ->
						cb JSON.stringify(objs)

			bindio()

	# TODO: REST API
	#for mname,model of schema

module.exports =
	db: mongoose
	dbinit: dbinit
	genapi: genapi
	checkUser: checkUser
	getUserById: getUserById
	setLogger: setLogger
	enableAPNs: ApiRequest.enableAPNs
	listUsers: listUsers
	listObjs: listObjs
	addUser: addUser
	addObj: addObj
	addPerm: addPerm
