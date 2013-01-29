#==========================================================================
# Socket.IO stuff

# Will get values of: 500, 1000, 2000, 4000, 8000, 16000, 32000, 60000
conntimeout = 500
iotimeout = null

socketretry = ->
	console.log 'Waiting ' + conntimeout / 1000 + ' seconds'

	clearTimeout iotimeout
	iotimeout = setTimeout () ->
		startIO()
	, conntimeout

	# Increase connection timeout by a factor of 2 up to a max of 60 seconds
	conntimeout = if conntimeout < 30000 then conntimeout * 2 else 60000

$(window).focus () ->
	return if not window.socket or conntimeout < 2000 or window.socket.socket.connected
	console.log 'Focus'
	conntimeout = 500
	clearTimeout iotimeout
	startIO()

onConnect = null
onDisconnect = null
syncProgress = -> false

# Tracking of how many objects are being sent down
incoming = 0
received = 0

window.syncConfig = (opts) ->
	#console.log opts
	onConnect = opts.online if opts.online
	onDisconnect = opts.offline if opts.offline
	syncProgress = opts.progress if opts.progress

window.setOnline = ->
	if window.socket.socket.connected is true
		onConnect?()
	else
		onDisconnect?()
		syncProgress 0

window.stopIO = ->
	window.socket.disconnect()
	delete window.socket
	clearTimeout iotimeout
	console.log "Socket.IO disabled"

# FIXME: Make this a Backbone model
window.pending =
	data: {}
	incr: (key, id) ->
		@data[key][id] = 1
		@update()
	set: (key, res) ->
		for obj in res
			@data[key][obj.id] = 1
		@update()
	decr: (key, id) ->
		delete @data[key][id]
		@update()
	update: ->
		# Set a delay before rendering, so that the indicator doesn't blink on & off if online
		self = this
		setTimeout () ->
			App.setPending(self.data)
		, 300

for key,val of dbschema.schema
	pending.data[key] = {}


getSyncData = (data, keyname, cb) ->

	persistence.transaction (tx) ->
		# Get the ID and edited from all objects that aren't new
		tx.executeSql "SELECT id,edited FROM `" + keyname + "`", [], (existing) ->
			#console.log 'Sync:', keyname, results
			data[keyname] = existing
			cb null, data

			query = window[keyname].prototype.dbmodel

			# Get all of the new & edited objects
			query.all().filter('edited', 'in', ['new', 'modified']).list (changed) ->
				#data[keyname] =
				#	existing: existing
				#	changed: changed

				# Send up the edited objects separately for now
				sendEdits keyname, changed

				#cb null, data

sendEdits = (keyname, results) ->
	pending.set keyname, results
	#console.log results
	for obj in results
		data = obj._data
		data._id = obj.id

		# Cleanup
		for key2,val2 of data
			delete data[key2] if val2?._constructor

		model = new window[keyname] data
		model.fetchAndSave () ->
			console.log 'Push Edit:', keyname, model

performSync = ->
	received = 0
	syncProgress 0.05

	# Get last edit date for all objects of this type - don't directly sync or persist embedded types/objects
	models = []
	for key,val of window.dbschema.schema
		models.push key unless embedded[key]

	async.reduce models, {}, getSyncData, (err, data) ->
		#console.log 'Sync:', data
		syncProgress 0.1
		socket.emit 'sync', data, () ->
			syncProgress 0.2

window.getUsers = (objid, cb) ->
	userid = JSON.parse(localStorage.user).username

	# FIXME: should follow access map for this
	query = """
		SELECT
			id AS _id, userid, firstname, lastname,
			(SELECT COUNT(*) FROM Right WHERE objid = '#{objid}' AND user = u.id) AS ok
		FROM
			User AS u
		WHERE
			userid <> '#{userid}'
	"""

	sql query, (res) ->
		myusers = []
		for obj in res
			#console.log obj.userid, obj.ok
			myusers.push new User obj
		cb myusers

saveObjData = (keyname, data) ->
	model = window.modelmap[data._id]
	if model
		model.trigger 'edit', data
	else
		model = new window[keyname] data
	model.saveLocal()

window.startIO = ->
	console.log "startIO"

	host = location.host
	host = 'taskbump.com' unless host.match /\w/

	window.socket = socket = io.connect location.protocol + '//' + host,
		'force new connection': true
		'reconnect': false

	socket.on 'connect', ->

		console.log 'Socket.IO connected'
		setOnline()
		conntimeout = 500
		clearTimeout iotimeout

		# Send the APN token up to the server if not done yet
		token = localStorage.apntoken
		if token and not localStorage.tokenSaved
			console.log 'Saving token:', token
			socket.emit 'apntoken', token, (res) ->
				localStorage.tokenSaved = true #if res.ok

		window.reindex()

		# Save the current user when sent
		socket.on 'auth', (user) ->
			window.CurrentUser = user
			localStorage.user = JSON.stringify(CurrentUser)

		for key,val of window.dbschema.schema
			bindio = ->
				keyname = key

				# Bulk sync
				socket.on 'sync:' + keyname, (data) ->
					console.log 'Sync:', keyname, data

					received += 1
					if incoming > 0
						syncProgress (received / incoming) * 0.6 + 0.3

					if received == incoming
						setTimeout ->
							updateDerived()
						, 100
						syncProgress 1

						# FIXME: This is hacky.  Should use an event
						App.setNotifyCnt()

					# get DB object, fetch, check
					#window[keyname].prototype.dbmodel.load data._id, (obj) ->
					#	console.log 'Loaded:', obj

					#	unless obj is null
					#		# Don't update local objects if they are new or have been modified
					#		edited = obj.edited
					#
					#		if edited is 'modified' or edited is 'new'
					#			console.error "Failed sync", obj
					#			return

					# FIXME: make sure local history isn't replaced

					setTimeout () ->
						saveObjData keyname, data
					, 50

				# Individual object push
				socket.on 'push:' + keyname, (data) ->
					console.log 'Server Push:', keyname, data

					# TODO: hack. add any new users to the 'AllUsers' collection
					AllUsers.add new User data if keyname is 'User'

					saveObjData keyname, data

					App.setNotifyCnt() if keyname is 'Notification'

			bindio()

		# Sync changes
		performSync()

	socket.on 'status', (cnt) ->
		incoming = cnt
		syncProgress if cnt is 0 then 1 else 0.3

	socket.on 'error', (err) ->
		setOnline()
		if err is 'handshake error'
			console.log 'Handshake:', err

			# FIXME: should just be able to use the router for this.
			#router.navigate 'login',
			#		trigger: true
			location.href = '#login'

			# Clear the DB on auth failure, and reload the page
			window.resetApp()
		else
			console.log 'Error ...', err
			socketretry()

	socket.on 'disconnect', () ->
		setOnline()
		console.log 'Disconnect ...'
		socketretry()

