# SQL Utility function
@sql = (query, msg) ->
	msg ?= ''
	#console.log query
	persistence.transaction (tx) ->
		tx.executeSql query, [], (results) ->
			if _.isFunction msg
				msg results
			else
				out = if results.length == 1 then results[0].val else results
				console.log msg, out

window.Offline = true

class SyncProgress
	data: {}

	init: =>
		for key,val of dbschema.schema
			@data[key] = {}

	incr: (key, id) =>
		@data[key][id] = 1
		@update()
	set: (key, res) =>
		for obj in res
			@data[key][obj.id] = 1
		@update()
	decr: (key, id) =>
		delete @data[key][id]
		@update()
	update: ->
		# Set a delay before rendering, so that the indicator doesn't blink on & off if online
		setTimeout () =>
			App.setPending(@data)
		, 300

class window.InSync

	# Socket.IO stuff
	online: false
	socket: null
	
	# Will get values of: 500, 1000, 2000, 4000, 8000, 16000, 32000, 60000
	conntimeout: 500
	iotimeout: null

	# Tracking of how many objects are being sent down
	incoming: 0
	received: 0

	# Models, properties, indexing, relationships
	pmodels: {}
	hasMany: {}
	embedded: {}
	mprops: {}
	fulltext: {}

	filteredWords: ['and', 'the', 'are']

	socketretry: =>
		console.log 'Waiting ' + @conntimeout / 1000 + ' seconds'
	
		clearTimeout @iotimeout
		@iotimeout = setTimeout () =>
			@startIO()
		, @conntimeout
	
		# Increase connection timeout by a factor of 2 up to a max of 60 seconds
		@conntimeout = if @conntimeout < 30000 then @conntimeout * 2 else 60000

	bindFocus: =>	
		$(window).focus () =>
			return if not @socket or @conntimeout < 2000 or @socket.socket.connected
			console.log 'Focus'
			@conntimeout = 500
			clearTimeout @iotimeout
			@startIO()

	# Default UI handlers
	onConnect: ->
	onDisconnect: ->
	syncProgress: ->

	syncConfig: (opts) ->
		#console.log opts
		@onConnect = opts.online if opts.online
		@onDisconnect = opts.offline if opts.offline
		@syncProgress = opts.progress if opts.progress

	setOnline: ->
		if @socket.socket.connected is true
			@online = true
			@onConnect?()
		else
			@online = false
			@onDisconnect?()
			@syncProgress 0

	stopIO: ->
		@socket.disconnect()
		@socket = null
		clearTimeout @iotimeout
		console.log "Socket.IO disabled"

	getSyncData: (data, keyname, cb) =>

		persistence.transaction (tx) =>
			# Get the ID and edited from all objects that aren't new
			tx.executeSql "SELECT id,edited FROM `" + keyname + "`", [], (existing) =>
				#console.log 'Sync:', keyname, results
				data[keyname] = existing
				cb null, data
	
				query = window[keyname].prototype.dbmodel
	
				# Get all of the new & edited objects
				query.all().filter('edited', 'in', ['new', 'modified']).list (changed) =>
					#data[keyname] =
					#	existing: existing
					#	changed: changed
	
					# Send up the edited objects separately for now
					@sendEdits keyname, changed
	
					#cb null, data

	sendEdits: (keyname, results) ->
		@pending.set keyname, results
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

	performSync: ->
		@received = 0
		@syncProgress 0.05
	
		# Get last edit date for all objects of this type - don't directly sync or persist embedded types/objects
		models = []
		for key,val of window.dbschema.schema
			models.push key unless @embedded[key]
	
		async.reduce models, {}, @getSyncData, (err, data) =>
			console.log 'Sync:', data
			@syncProgress 0.1
			@socket.emit 'sync', data, () =>
				@syncProgress 0.2

	getUsers: (objid, cb) ->
		@userid = JSON.parse(localStorage.user).username

		# FIXME: should follow access map for this
		query = """
			SELECT
				id AS _id, userid, firstname, lastname,
				(SELECT COUNT(*) FROM Right WHERE objid = '#{objid}' AND user = u.id) AS ok
			FROM
				User AS u
			WHERE
				userid <> '#{@userid}'
		"""
	
		sql query, (res) ->
			myusers = []
			for obj in res
				#console.log obj.userid, obj.ok
				myusers.push new User obj
			cb myusers

	saveObjData: (keyname, data) =>
		model = new window[keyname] data

		model.saveLocal()

	startIO: ->
		console.log "startIO"
	
		@host = location.host
	
		@socket = io.connect location.protocol + '//' + @host,
			'force new connection': true
			'reconnect': false

		window.BaseModel.socket = @socket
	
		@socket.on 'connect', =>
	
			console.log 'Socket.IO connected'
			@setOnline()
			@conntimeout = 500
			clearTimeout @iotimeout
	
			# Send the APN token up to the server if not done yet
			@token = localStorage.apntoken
			if @token and not localStorage.tokenSaved
				console.log 'Saving token:', @token
				@socket.emit 'apntoken', @token, (res) ->
					localStorage.tokenSaved = true #if res.ok
	
			@reindex()
	
			# Save the current user when sent
			@socket.on 'auth', (user) ->
				window.CurrentUser = user
				localStorage.user = JSON.stringify(window.CurrentUser)
	
			for key,val of dbschema.schema
				bindio = =>
					keyname = key
	
					# Bulk sync
					@socket.on 'sync:' + keyname, (data) =>
						console.log 'Sync:', keyname, data
	
						@received += 1
						if @incoming > 0
							@syncProgress (@received / @incoming) * 0.6 + 0.3
	
						if @received == @incoming
							setTimeout =>
								@updateDerived()
							, 100
							@syncProgress 1
	
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
	
						setTimeout () =>
							@saveObjData keyname, data
						, 50
	
					# Individual object push
					@socket.on 'push:' + keyname, (data) =>
						console.log 'Server Push:', keyname, data
	
						# TODO: hack. add any new users to the 'AllUsers' collection
						AllUsers.add new User data if keyname is 'User'
	
						@saveObjData keyname, data
	
						App.setNotifyCnt() if keyname is 'Notification'
	
				bindio()
	
			# Sync changes
			@performSync()
	
		@socket.on 'status', (cnt) =>
			@incoming = cnt
			@syncProgress if cnt is 0 then 1 else 0.3
	
		@socket.on 'error', (err) =>
			@setOnline()
			if err is 'handshake error'
				console.log 'Handshake:', err

				# FIXME: should just be able to use the router for this.
				#router.navigate 'login',
				#		trigger: true
				location.href = '#login'
	
				# Clear the DB on auth failure, and reload the page
				@resetApp()
			else
				console.log 'Error ...', err
				@socketretry()
	
		@socket.on 'disconnect', () =>
			@setOnline()
			console.log 'Disconnect ...'
			@socketretry()
	
	
	dbinit: =>
		app =
			name: "syncapp"
			desc: "Offline Application"

		# TODO: only use this if offline mode is enabled

		# persistence.js Web SQL storage
		persistence.debug = false

		persistence.store.websql.config(persistence, app.name,
			app.desc, 5 * 1024 * 1024);

		dialect = persistence.store.websql.sqliteDialect

		@HistObj = persistence.defineMixin 'HistObj',
			history: "JSON"

		@SyncObj = persistence.defineMixin 'SyncObj',
			edited: "TEXT"

		# This is copied & hacked from the persistence.search.js file
		persistence.flushHooks.push (session, tx, callback) =>
			mqueries = []
			for id,obj of session.getTrackedObjects()

				for p,stuff of obj._dirtyProperties

					continue unless p in @fulltext[obj._type]
					#console.log obj, id, p, fulltext[obj._type]

					mqueries.push(['DELETE FROM TextIndex WHERE `entityId` = ? AND `prop` = ?', [id, p]])
					occurrences = searchTokenizer(obj._data[p])
					for word,cnt of occurrences
						qx = ['INSERT INTO TextIndex VALUES (?, ?, ?, ?, ?)', [obj.id, obj._type, p, word, cnt]]
						#console.log qx
						mqueries.push qx
			mqueries.reverse()
			persistence.executeQueriesSeq(tx, mqueries, callback)

	dbindexing: =>
		# Full-text index table
		queries = []

		ixfields = [['entityId', 'CHAR(32)'], ['type', 'VARCHAR(100)'], ['prop', 'VARCHAR(100)'], ['word', 'VARCHAR(100)'], ['occurrences', 'INT']]
		
		#queries.push([dialect.createTable('TextIndex', ixfields, ['entityId', 'prop', 'word']), null])
		queries.push([dialect.createTable('TextIndex', ixfields), null])
		queries.push([dialect.createIndex('TextIndex', ['type', 'prop', 'word']), null])
		queries.push([dialect.createIndex('TextIndex', ['prop', 'word']), null])
		queries.push([dialect.createIndex('TextIndex', ['word']), null])
		queries.push([dialect.createIndex('TextIndex', ['entityId']), null])
		persistence.generatedTables['TextIndex'] = true;
		queries.reverse()

		persistence.transaction (tx) ->
			persistence.executeQueriesSeq(tx, queries)

	modelSetup: =>
		# Save pointer for 'initialize' function
		
		embedded = @embedded

		# Generate the properties that will be used for the Backbone models
		for key,schema of dbschema.schema

			@fulltext[key] = []

			genprops = =>

				# Save the raw schema on to the Backbone object for later
				props =
					schema: schema
					derived: []
					dfields: []

				keyname = key
				pschema = {}
				@hasMany[key] ?= []

				defaults = {}
				for field,obj of schema

					# Skip index information & private fields
					continue if field is 'indexes' or obj.private

					defaults[field] = obj.default if obj.default?

					# Schema for persistence.js

					# Base types - have a corresponding JS function
					if typeof obj is 'function'

						pschema[field] = switch obj
							when Number then 'INT'
							when Object then 'JSON'
							when Boolean then 'BOOL'
							else 'TEXT'

					else if typeof obj is 'function' or obj.type and typeof obj.type is 'function'
						# FIXME: this is duplicated above
						pschema[field] = switch obj.type
							when Number then 'INT'
							when Object then 'JSON'
							when Boolean then 'BOOL'
							else 'TEXT'

						#console.log key, field, obj, pschema[field]

						# If a derived type with a refresh value, then add an '_updated' timestamp column
						if obj.derived and obj.refresh
							pschema[field + '_updated'] = 'INT'

					# Lists of object IDs
					else if obj instanceof Array
						pschema[field] = 'JSON'

					# Embedded objects
					else if obj.embedded
						@embedded[obj.type] = 1
						nt =
							type: key
							field: field

						if @hasmany[obj.type] instanceof Array
							@hasMany[obj.type].push nt
						else
							@hasMany[obj.type] = [nt]

					# References to other types
					else if dbschema.schema[obj] or (obj.type and dbschema.schema[obj.type])
						obj = obj.type if obj.type

						# FIXME: this is hacky.
						fname =	key
						mtype = obj
						if key is obj
							fname = field
							mtype = field

						@hasMany[key].push
							type: obj
							refname: mtype.toLowerCase()
							field: fname.toLowerCase() + 's'

					# Other fields?
					else
						pschema[field] = 'TEXT'

					if obj.fulltext
						@fulltext[key].push field


				pschema.created = "TEXT"
				pschema.creator = "TEXT"

				#console.log key, pschema
				@pmodels[key] = pmodel = props.dbmodel = persistence.define key, pschema
				pmodel.is(@HistObj) unless key is 'Notification'

				props.key = key.charAt(0).toLowerCase() + key.slice(1)
				props.initialize = (data) ->

					unless @id
						# Generate a globally unique ID that will be used for local storage and for Mongo DB
						newid = (new ObjectId()).toString()
						@set '_id', newid
						@set 'creator', window.CurrentUser.id
						@set 'created', new Date()
						@set 'edited', 'new' unless embedded[keyname]
						@set 'history', []

						for keyn,dflt of defaults
							val = if _.isFunction(dflt) then dflt() else dflt
							@set keyn, val

					@bind 'edit', @update, this

				# TODO: change all of these methods to accept callbacks

				for field,obj of schema
					# Add the methods for embedded objects
					if obj.embedded
						name = field.charAt(0).toUpperCase() + field.slice(1, field.length - 1)

						# Create a new embedded object & set the parent pointer.  Object not saved yet.
						bindp = ->
							fname2 = field
							typename = obj.type
							(data) ->
								model = new window[typename] data

								# Add the new model to the list of embedded objects
								@push fname2, model

								# Add a history object to the model
								model.addHistory data

								# Add a history object to the parent
								hist = {}
								hist[fname2] =
									added: model.id
								@addHistory hist

								# Set the parent pointer
								model._parent = this
								model._list = fname2

								model

						props['add' + name] = bindp() #field, obj.type

						# Fetch an embedded object by the specified properties
						props['get' + name] = (check) ->
							objs = @get(field).filter (eobj) ->
								for mykey,myval of check
									return false unless eobj[mykey] == myval
								true
							return null unless objs.length
							model = new window[obj.type] objs[0]
							model._parent = this
							model._list = field
							model

					# Add 'get' method for object references
					if dbschema.schema[obj] or dbschema.schema[obj.type]
						obj = obj.type if obj.type

						name = field.charAt(0).toUpperCase() + field.slice(1)
						#console.log key, ' : get' + name

						bindp = ->
							fname3 = field
							cname = dbschema.schema[key][field]
							cname = cname.type if cname.type

							#console.log key, 'get' + name, cname
							(cb) ->
								if window.Offline
									#console.log fname, cname
									@dbmodel.load @get(fname3), (res) ->
										newobj = new window[cname] res._data
										#console.log fname, ':', newobj
										cb(newobj)

								else
									false

						props['get' + name] = bindp()

				props

			@mprops[key] = genprops()

		# FIXME: move the core code here to Base.coffee and just create proxy functions here
		# Create the accessor methods for embedded properties and other one-to-many relationships
		for type,list of @hasMany

			for obj in list
				refname = obj.type
				#console.log refname, obj.field, type, refname.toLowerCase(), obj

				# Get all of the embedded objects
				bindp = ->
					fname = obj.field
					mname = type
					z = dbschema.schema[refname][fname]
					embed = if z then z.embedded else false
					#console.log refname, fname, embed
					(opts, cb) ->

						if _.isFunction(opts)
							cb = opts
							opts = {}

						if window.Offline
							# TODO: kind of a hack.  new objects won't have this yet ...
							return cb [] unless @dbobj

							objs = @get fname

							#console.log mname, fname, opts, objs

							# Already pre-fetched ...
							if objs instanceof Array

								# TODO: This is kind of hacky - should be able to sort earlier on pre-fetch for embedded objects
								if opts.order
									sortkey = null
									for skey, asc of opts.order
										sortkey = skey

									objs.sort (a, b) ->
										if a.get(sortkey).toLowerCase() < b.get(sortkey).toLowerCase() then -1 else 1

								return cb objs

							# Extend the DBQueryCollection object for this property with the specified options
							#console.log 'Query:', this, @dbobj, mname, fname
							query = @dbobj[fname]
							query = @dbQuery query, opts

							self = this
							query.list (results) ->
								timelog('Get ' + fname)
								#console.log results
								models = []
								for obj in results
									data = obj._data
									data._id = obj.id

									#console.log mname, data

									if opts.dataonly
										models.push data
									else
										model = new window[mname] data
										model._parent = self if embed
										model._list = fname
										models.push model

								timelog(mname + if opts.dataonly then ' objects' else ' models')

								#console.log models
								self.set fname, models unless opts.dataonly

								cb models

						else
							objs = []
							list = @get fname
							return [] unless list?.length
							for odata in list
								model = new window[obj.type] odata
								model._parent = this
								model._list = fname
								objs.push model
							cb objs

				typename = 'get' + obj.field.charAt(0).toUpperCase() + obj.field.slice(1)
				#console.log refname, typename
				@mprops[refname][typename] = bindp()


		# Indexing
		for mname,schema of dbschema.schema

			# TODO: not sure if this makes an actual difference ... maybe if declared unique?
			# Special index for sync: keep the edited values in the actual index
			@pmodels[mname].index ['id', 'edited'], { unique: true } unless @embedded[mname]

			for field,val of schema
				if val.index and not val.private
					@pmodels[mname].index field

			# multi-column indexes
			if schema.indexes
				for flist in schema.indexes
					@pmodels[mname].index flist

		# Derived props
		for mname,schema of dbschema.schema
			for field,val of schema
				if val.derived
					refs = if val.references instanceof Array then val.references else [val.references]
					for refname in refs

						if refname is 'self'
							@mprops[mname].dfields.push field
						else
							@mprops[refname].derived.push
								type: mname
								field: field

		# Mixins
		for fname,mixin of dbschema.mixins
			mobj = {}

			mobj[fname] =
				switch mixin.type
					when Boolean then "BOOL"
					else "TEXT"

			#console.log fname, mobj, mixin.models
			PMixin = persistence.defineMixin fname, mobj

			for mname in mixin.models
				@pmodels[mname].is(PMixin)
				# FIXME: check for 'index:true' for this
				@pmodels[mname].index fname


		# Create the Backbone models
		for key,props of @mprops
			window[key] = BaseModel.extend props

		#console.log hasMany
		# Relationships for persistence.js
		for type,list of @hasMany
			for obj in list
				refname = obj.type
				m1 = window[refname].prototype
				m2 = window[type].prototype
				#console.log refname, obj.field, type, obj.refname
				m1.dbmodel.hasMany obj.field, m2.dbmodel, obj.refname || m1.key


		# Add the 'edited' field to all top-level models
		for key,schema of dbschema.schema
			continue if @embedded[key]
			@pmodels[key].is(@SyncObj)
			@pmodels[key].index 'edited'

	fillSchema: =>

		# FIXME: hack in a copy of the 'Right' and 'Notification' schemas - this code is duplicated in 'mongodb.coffee'
		dbschema.schema.Right =
			user:
				type: ObjectId
				index: true
			objid:
				type: ObjectId
				index: true
			type:
				type: String
				index: true
			access:
				type: String
				default: "full"
				enum: ["full"]
	
		dbschema.schema.Notification =
			objid:
				type: ObjectId
				index: true
				required: true
			type:
				type: String
				index: true
				required: true
			status:
				type: String
		#		default: "new"
		#		enum: ["new", "viewed"]
		#		required: true
			action:
				type: String
				enum: ["added", "edited", "shared"]
				required: true
			data: Object

	#==========================================================================
	# DB Utils

	getTableStats: (key) =>
		sql 'SELECT COUNT(*) AS val FROM `' + key + '`', (results) ->
			console.log ' ', key, results[0].val

	dbstats: =>
		console.log 'Models:'
		getTableStats(key) for key,val of dbschema.schema

		sql 'SELECT type, COUNT(*) sum FROM TextIndex GROUP BY type', (results) ->
			console.log 'Text Index:'
			for row in results
				console.log ' ', row.type, row.sum

	getunindexed: =>
		# FIXME: use async here to get full list for a callback
		for key,val of dbschema.schema
			continue unless @fulltext[key].length

			query = 'SELECT id FROM `' + key + '` WHERE id NOT IN (SELECT DISTINCT entityId FROM TextIndex WHERE type="' + key + '")'
			func = (key) ->
				sql query, (results) ->
					console.log 'Unindexed: ' + key, results.length

			func key
		return

	# Functions from persistence.search.js

	# FIXME: need an english word list to really do this right
	# Some extremely basic & crude stemming
	normalizeWord: (word, filterShortWords) =>
		if word not in @filteredWords or filterShortWords and word.length < 3
			word = word.replace /ies$/, 'y'
			word = if word.length > 3 then word.replace(/s$/, '') else word
			word
		else
			false

	searchTokenizer: (text) =>
		return [] unless text

		words = text.toLowerCase().split(/[^\w\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF]+/)
		wordDict = {}
		for word in words
			word = normalizeWord word
			if word
				if wordDict[word]
					wordDict[word]++
				else
					wordDict[word] = 1
		wordDict

	reindex: =>
		# FIXME: use async here to get full list for a callback
		for key,val of dbschema.schema
			fields = @fulltext[key]

			continue unless fields.length

			#console.log 'Re-index:', key, fields

			query = 'SELECT id,' + fields.join(',') + ' FROM `' + key + '` WHERE id NOT IN (SELECT DISTINCT entityId FROM TextIndex WHERE type = "' + key + '")'
			#console.log query
			# TODO: wrap the rest of this in to an indexing function
			func = (key, fields) ->
				sql query, (results) ->
					return unless results.length
					@indexResults key, fields, results

			func key, fields

	runQueries: (queries) =>
		persistence.transaction (mtx) =>
			persistence.executeQueriesSeq mtx, queries

	indexResults: (key, fields, results) =>
		#console.log 'Re-indexing: ', key, results.length
		queries = []
		for res in results
			for fname in fields

				# Skip empty or undefined fields
				continue unless res[fname]

				wordcnt = searchTokenizer res[fname]
				for word,cnt of wordcnt
					q2 = ["INSERT INTO TextIndex VALUES (?, ?, ?, ?, ?)", [res.id, key, fname, word, cnt]]
					#console.log q2
					queries.push q2

		@runQueries queries

	#==========================================================================
	# Recalcuate all derived properties

	fetchAndUpdate: (key, fields, full) =>
		for fname in fields
			console.log key, 'update' + ucword(fname)
			window[key].prototype['update' + ucword(fname)](full)

	updateDerived: (full) =>
		for key,schema of dbschema.schema

			# Check for derived fields
			fields = []
			for fname,val of schema
				fields.push fname if val.derived

			# Fetch all of the objects and update
			@fetchAndUpdate(key, fields, full) if fields.length

	# Reset the DB
	resetApp: (reload) =>
		#localStorage.clear()
		persistence.transaction (tx) ->
			for key,val of dbschema.schema
				tx.executeSql "DROP TABLE `" + key + "`"

		location.reload() if reload

	init: =>
		@pending = new SyncProgress()
		@pending.init()

		@dbinit()
		@fillSchema()
		@modelSetup()

		# Pointer for model
		BaseModel.sync = this

		# Persist schema to DB
		persistence.schemaSync()

		@startIO()
