window.timelog = ->

class window.BaseModel extends Backbone.Model
	idAttribute: '_id'

	@getBtype: ->
		@key.charAt(0).toUpperCase() + @key.slice(1)

	getBtype: ->
		@key.charAt(0).toUpperCase() + @key.slice(1)

	@find: (id, cb) ->
		mname = @getBtype()

		# Fetch from server or from local sqlite DB
		if window.Offline
			@dbmodel.load id, (dbobj) =>
				data = dbobj._data
				data._id = dbobj.id

				# Create the backbone object
				obj = new window[@getBtype()] data

				# Save pointer to persistence.js object for later
				obj.dbobj = dbobj

				cb obj
		else

			sync.socket.emit 'get:' + mname, id, (data) ->
				obj = new window[mname] JSON.parse(data)
				cb obj

	@dbQuery: (query, opts) ->
		unless opts
			opts = query
			db = @dbmodel
			query = db.all()

		if opts.filter
			for key,val of opts.filter
				if typeof val is 'object'
					query = query.filter(key, val.op, val.value)
				else
					query = query.filter(key, '=', val)

		if opts.limit
			query = query.limit opts.limit

		if opts.offset
			query = query.skip opts.offset

		if opts.order
			for key,val of opts.order
				asc = if val is 'ASC' then true else if val is 'DESC' then false else throw Error('Invalid sort order')
				query = query.order key, asc
		query

	# FIXME: remove the duplicate function from BaseList
	@fetch: (opts, cb) ->
		unless cb
			cb = opts
			opts = {}

		typename = @getBtype()

		timelog('Fetching ' + typename)
		# Fetch from server or from sqlite DB
		if window.Offline
			query = @dbQuery opts
			query.list (results) ->
				timelog('Fetched ' + typename)

				list = results.map (obj) ->
					data = obj._data
					data._id = obj.id

					model = new window[typename] data
					model.dbobj = obj
					model

				timelog(typename + ' objects')
				cb list

		else
			sync.socket.emit 'list:' + typename, (data) ->
				JSON.parse(data)

	prefetch: (cb) ->
		cb ?= -> false

		list = []
		for key,val of window.dbschema.schema[@getBtype()]
			continue unless val.embedded
			list.push
				key: key
				val: val

		# FIXME: use the DbQueryCollection on the properties directly ... don't even need to iterate schema?

		fetchlist = (keyval, cb2) =>
			{key, val} = keyval

			if val.embedded
				db2 = window[val.type].prototype.dbmodel
				#console.log self.key, val.type
				q2 = db2.all().filter(@key, '=', @id).list (results) =>
					objs = []
					for obj in results

						# FIXME: move in to a method
						data = obj._data
						data._id = obj.id
						newobj = new window[val.type] data

						newobj._parent = this
						newobj._list = key
						objs.push newobj
					@set key, objs
					cb2 false

		async.forEach list, fetchlist, cb


	getDbObj: =>
		obj = @toJSON()
		obj.id = obj._id
		delete obj._id

		# Set the field name for the parent for persistence
		if @_parent
			obj[@_parent.key] = @_parent.id

		# Perform any additional persistence of embedded documents, clearing them out during the process
		@cleanup(obj)

	# Persist to the local Web SQL database
	saveLocal: (noflush) =>

		# Update any derived fields on self
		for fname in @dfields
			@['calc' + ucword(fname)]()

		# Update any derived fields on referenced objects
		for dprop in @derived

			# FIXME: this is a hack to look up the ID property on the current object
			# - fix 'get' method to have a 'dbobj'

			#this['get' + dprop.type] (obj) ->
			window[dprop.type].prototype.find @get(dprop.type.toLowerCase()), (obj) =>
			#this['get' + dprop.type] (obj) ->
				fname = ucword dprop.field
				obj['calc' + fname] this
				obj.saveLocal true

		#if @dbobj
		#	for key,val of @getDbObj()
		#		@dbobj[key] = val
		#	persistence.flush()
		#else
		obj = @getDbObj()

		# FIXME: don't save locally if locally edited

		#console.log obj
		dbobj = new @dbmodel obj
		#console.log 'Save local:', @key, dbobj
		persistence.add dbobj

		@persist @toJSON()

		unless noflush
			type = @getBtype()
			persistence.flush () ->
				# FIXME: should use an event here
				App.setNotifyCnt() if type is 'Notification'

	# FIXME: this isn't efficient to iterate over the schema every time - save list of embedded objects once per model
	persist: ->
		for key,val of window.dbschema.schema[@getBtype()]
			if val.embedded
				objs = @get key
				continue unless objs
				for obj in objs
					#console.log 'Embedded:', key, obj
					#console.log val.type, @key, this, obj, model
					unless obj.saveLocal
						obj = new window[val.type] obj
						obj._parent = this
						obj[@key] = @id

					obj.saveLocal()

	# TODO: removed derived properties from data sent to server
	cleanup2: (obj) ->
		res = {}
		schema = window.dbschema.schema[@getBtype()]
		#console.log 'Clean:', schema, obj
		for key,val of obj
			# FIXME: This is rather hacky - what about mixins?
			res[key] = val if schema[key] or key.match /^(_id|created|edited|creator|history)$/
		res

	cleanup: (obj) =>
		schema = window.dbschema.schema[@getBtype()]
		res = {}
		#console.log 'Clean:', schema, obj
		for key,val of obj
			res[key] = val

		for key,val of schema
			if val.embedded
				delete res[key]
		res

	setData: (data) =>
		#console.log 'setData:', @key, @id, data
		@set data

		# Create models for the embedded properties
		for key,val of window.dbschema.schema[@getBtype()]
			continue unless val.embedded and data[key]?.length
			list = []
			for obj in data[key]
				# FIXME: This is duplicated in many places
				model = new window[val.type] obj
				model._parent = this
				model._list = key

				list.push model
			@set key, list

		@saveLocal()

	# Replace the model properties with the ones received - in memory and in local storage
	update: (data) =>
		console.log 'Update:', @key, @id, data

		cdata = @cleanup(data)

		@setData data

	push: (name, val) =>
		console.log 'push:', @getBtype(), this, name, val
		list = @get name
		list.push val
		@set name, list

	addHistory: (changes) =>
		# FIXME: hack - don't save history if case notes.  this should be determined by the DB schema.
		return if changes.notes and @getBtype() is 'Case'

		return if changes == {} or changes is false

		edit =
			_id: (new ObjectId()).toString()
			created: new Date()
			creator: window.CurrentUser.id
			changes: changes

		# Add the history object locally
		@push 'history', edit

	# FIXME: review Backbone.save and Backbone.sync and see where all of this should actually go ...
	save: (edited, cb) =>

		edited ?= {}
		if _.isFunction edited
			cb = edited
			edited = {}

		type = @getBtype()

		# FIXME: don't continue if there were no edits

		for key,val of edited
			@set key, val

		@addHistory edited unless type is 'Notification'

		# If this is an embedded object, replace the object on the parent, and set the save pointer
		if @_parent
			parent = @_parent
			mykey = @key
			parent.prefetch =>
				# Replace the embedded object with the edited one
				list = parent.get @_list
				parent.set @_list, []
				for obj in list
					parent.push @_list, if obj.id == @id then @ else obj
				@saveLocal()

				parent.editSave cb
		else
			@editSave cb

	editSave: (cb) =>
		@setEdited()
		@saveLocal()
		@saveUp cb

	setEdited: =>
		if @get('edited') != 'new'
			@set 'edited', 'modified'
		sync.pending.incr @getBtype(), @id

	getJSON: =>
		data = @toJSON()
		for key,val of data
			delete data[key] if val?._constructor
		data

	saveUp: (cb) =>
		if sync.socket?.socket.connected

			cmd = if @get('edited') is 'new' then 'add' else 'edit'

			sdata = @cleanup2 @getJSON()
			console.log 'Save (' + cmd + '): ', @key, sdata

			sync.socket.emit cmd + ':' + @getBtype(), sdata, (resp) =>
				data = JSON.parse(resp)

				if data.error
					@merge data.model
				else if resp is false
					console.log 'Error saving'
				else
					sync.pending.decr @getBtype(), @id

					# Update any attributes sent back from the server
					@update data

		cb?()

	merge: (data) ->
		alert 'Sync error'

	getDiffs: (data) =>
		# Combine the history arrays already
		hids = {}
		for hist in @get 'history'
			hids[hist._id] = true
		for hist in data.history
			@push 'history', hist unless hids[hist._id]
		# FIXME: not sorting the history right now ...


		diffs = {}

		for key,val of data
			continue if key is 'history' or val instanceof Array

			oldval = @get key

			# FIXME: get UTC Date here ...
			#val = new Date(val) if oldval.getDays
			if val and not val instanceof Array and val.toString().match /Z$/
				val = new Date(val)
				oldval = new Date(oldval)

			continue unless val or oldval

			#console.log key, oldval, val

			# Values are different: date, object, string
			if key != 'edited'
				
				if val and not oldval or
				   oldval and not val or
				   val.getDate and val.getTime() - oldval.getTime() or
				   not val.getDate and _.isObject(val) and JSON.stringify(val) != JSON.stringify(oldval) or
				   not val.getDate and not _.isObject(val) and val != oldval

					diffs[key] =
						a: oldval
						b: val

		diffs


	# Share an object with another user
	share: (user) =>

		data =
			type: @getBtype()
			objid: @id
			user: user.id

		rt = new Right

		@addHistory
			shared: user.id

		@editSave -> false

		# FIXME: model shouldn't be calling view code here - use bind/trigger
		rt.save data, (result) ->
			App.setStatus 'Case shared with ' + user.get('userid')

	# Pre-fetch a model's embedded objects and save the model to the server
	fetchAndSave: (cb) =>
		@prefetch =>
			@saveUp()
			cb()
