window.BaseList = Backbone.Collection.extend
	parse: (resp) ->
		resp = JSON.parse(resp)	if typeof resp is "string"
		resp[@key]

	# FIXME: merge these two methods
	fetchObjs: (opts, cb) ->
		unless cb
			cb = opts
			opts = {}

		typename = @key.charAt(0).toUpperCase() + @key.slice(1)

		# Fetch from server or from sqlite DB
		if window.Offline
			query = window[typename].prototype.dbQuery opts
			query.list (results) ->
				timelog('Fetch ' + typename)

				list = results.map (obj) ->
					data = obj._data
					data._id = obj.id
					data

				timelog(typename + ' objects')
				cb list

		else
			window.socket.emit 'list:' + typename, (data) ->
				JSON.parse(data)

	#initialize: ->
	fetch: (opts, cb) ->
		unless cb
			cb = opts
			opts = {}

		self = this
		@reset()
		typename = @key.charAt(0).toUpperCase() + @key.slice(1)
		#console.log typename

		# Fetch from server or from sqlite DB
		if window.Offline
			query = window[typename].prototype.dbQuery opts
			query.list (results) ->
				timelog('Fetch ' + typename)
				results.forEach (obj) ->
				# Set the ID attribute to match Mongo, and what Backbone expects
					data = obj._data
					data._id = obj.id

					model = new window[typename] data
					#console.log typename, model, data
					model.dbobj = data
					self.add model

					# Fetch embedded objects if requested
					model.prefetch() if opts.prefetch

				#console.log typename, self.models
				timelog(typename + ' models')
				cb? self.models

		else
			window.socket.emit 'list:' + typename, (data) ->
				self.add JSON.parse(data)
				cb? self.models




