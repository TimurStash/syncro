mongoose = require 'mongoose'
async = require 'async'

ObjectId = mongoose.Types.ObjectId


class ApiRequest

	#===========================================================
	# Static methods

	@setData: (@dbschema, @models, @logger) ->
		# Patch
		@db = require './storage/mongodb'
		for mname in ['Right', 'Notification', 'ApnToken']
			@db[mname] = @models[mname].model

	@enableAPNs: ->
		@logger.notice 'Enabling Apple Push Notifications'
		@apns = require '../syncro/apns'

	@bind: (socket, modelname) ->
		(data, cb) ->
			req = new ApiRequest socket, modelname
			req.data = data
			req.cb = cb
			req

	@setLogger: (@logger) ->

	#===========================================================
	# Constructor

	constructor: (@socket, @modelname) ->
		@user = @socket?.handshake.user
		@uid = @user?._id

		s = ApiRequest.dbschema

		# FIXME: use {x} = notation here
		@gschema = s.schema
		@gmap = s.map
		@skipn = s.skipnotify

		@cb = ->

		# FIXME this is rather ugly
		@db = ApiRequest.db
		@logger = ApiRequest.logger
		@models = ApiRequest.models
		@apns = ApiRequest.apns
		if @modelname
			@model = @models[@modelname].model

	#===========================================================
	# Utility

	cmdErr: (err) =>
		@logger.error err
		# TODO: send something back using socket.io
		@cb false

	#===========================================================
	# Main API methods

	add: =>

		mapval = @gmap[@modelname]

		# Skip normal rights verification for object sharing and top-level objects
		return @addObject @modelname, @data if @modelname is 'Right' or mapval is true

		#console.log 'Check:', @modelname, @data

		@checkPerms @user, @modelname, @data, (err, res) =>
			throw err if err?

			return @cmdErr 'Insufficient rights: ' + @user.userid +  ' : Add : ' + @modelname unless res

			#console.log 'Perms: ' + res
			@addObject @modelname, @data


	edit: =>
		id = @data._id

		# Handle Notifications separately
		if @modelname is 'Notification'
			@db.Notification.findById id, (err, obj) =>
				return @cmdErr err if err?

				unless @isCurrUser(obj.user)
					return @cmdErr 'Invalid user for notification: ' + id

				# FIXME: Since we aren't saving history (yet), for this, we don't have an actual date for when the notification was viewed
				obj.edited = new Date()
				obj.status = @data.status

				@logger.info 'Updating Notification: ' + id
				@saveReply 'edited', {}, @modelname, obj

		else

			# Check the permissions
			@getUsers @modelname, [id], (userids) =>

				# Make sure current user is in list
				ok = false
				for uid in userids
					ok = true if @isCurrUser(uid)

				return @cmdErr 'Insufficient rights: ' + @user.userid + ' : Edit : ' + @modelname unless ok

				@logger.info "Edit: " + @modelname + ' : ' + id
				@model.findById id, (err, obj) =>
					return @cmdErr err if err?
					return @cmdErr 'Edit: Could not find object: ' + @modelname + ' : ' + id unless obj

					obj.edited = new Date()

					return unless @applyEdits @uid, @modelname, obj, @data

					ndata = @data.history[@data.history.length - 1]

					@saveReply 'edited', ndata, @modelname, obj

	#===========================================================
	# Helper methods

	applyEdits: (userid, modelname, obj, data) =>
		unless @verifyEdit 'history', obj, data
			@logger.info "Conflict: " + modelname + ' : ' + data._id

			# FIXME: convert to object here
			@cleanup modelname, userid, obj
			@cb JSON.stringify
				error: 'merge'
				model: obj
			return false

		# Apply the edits
		for key,val of data
			# Skip the special fields
			continue if key is 'edited' or key is 'history'

			peruser = @gschema[modelname][key]?.peruser

			# Embedded objects
			if val instanceof Array

				# FIXME: Skip arrays of ObjectIDs for now
				continue if val.length and not val[0].history

				# Get ID map for sent objects
				ids = {}
				for obj2 in obj[key]
					ids[obj2._id] = obj2

				for eobj in val
					#console.log eobj

					# FIXME: should call this in the else block, and only if value is changed
					obj.markModified? key

					nobj = ids[eobj._id]

					if nobj
						# FIXME: Handle case where object is not sent up for some reason
						return false unless @applyEdits userid, modelname, nobj, eobj
					else
						obj[key].push eobj

				# Per-user properties
			else if peruser
				# Initialize the per-user array if not already set
				obj[key] ?= []

				# FIXME: clean up this nasty array code
				if val
					#console.log 'Per-user:', modelname, key, obj, userid, obj[key], typeof obj
					found = false
					for aval in obj[key]
						found = true if aval.toString() == userid.toString()

					obj[key].push userid unless found
				else
					mvals = []
					for aval in obj[key]
						mvals.push aval unless aval.toString() == userid.toString()
					obj[key] = mvals

				obj.markModified? key

				# FIXME: translate history object as well

			else
				#console.log key, val
				obj[key] = val

		true

	# Compare a list of sent documents against existing set.  Add any new edits.
	# Reject if sent list is missing any old docs.
	verifyEdit: (key, obj, data) =>

		# Get IDs of sent history
		sids = {}
		for doc in data[key]
			sids[doc._id] = doc

		# Get IDs of existing history
		ids = {}
		for doc in obj[key]
			ids[doc._id] = doc

		#console.log key
		#console.log sids
		#console.log ids

		# Check for any history entries on the server that weren't sent by the client
		for id,val of ids
			#console.log id, val unless sids[id]
			if key is 'history' and not sids[id]
				for a,b of val.changes
					# FIXME: This is a bit of a hack
					return false unless b.added

			else if key isnt 'history' and ids[id] and sids[id]
				return false unless @verifyEdit 'history', ids[id], sids[id]

		modified = false

		# Add any new objects to the array, and sort by creation date
		for doc in data[key]
			unless ids[doc._id]
				obj[key].push doc
				modified = true

		if modified
			obj[key].sort (a, b) ->
				new Date(a.created) - new Date(b.created)
			obj.markModified? key

		true

	isCurrUser: (uid) =>
		uid.toString() == @uid.toString()


	sendToAll: (action, data, modelname, obj, cb) =>
		# Get users with access to this object
		@getUsers modelname, [obj._id], (userids) =>
			return @cmdErr 'Could not get users for object: ' + modelname + ' : ' + obj._id, cb err if err?

			for uid in userids
				mobj = obj.toObject()
				@cleanup modelname, uid, mobj

				skip = @isCurrUser(uid) or @skipn[modelname]?[action]
				@addNotify action, data, uid, modelname, obj unless skip

				# Send the actual object down to the user
				# TODO: only push to users that are connected - check the socket rooms
				@logger.debug 'Push: ' + uid + ' : ' + modelname + ' : ' + obj._id
				@socket.broadcast.to(uid).emit 'push:' + modelname, mobj

			cb()

	# Add notification object for a user and push it to clients
	addNotify: (action, data, uid, modelname, obj) =>
		@sendNotify uid, modelname,
			action: action
			type: modelname
			user: uid
			objid: obj._id
			creator: @uid
			data: data

	sendNotify: (uid, modelname, data) =>
		notify = new @db.Notification data
		notify.save (err) =>
			if err
				@logger.error "Could not create notification: #{@modelname} : #{obj._id}" + JSON.stringify(err)
				return

			# Don't send the (redundant) user field to the clients
			obj = notify.toObject()
			delete obj.user

			# Push to user as well
			@logger.debug 'Notify: ' + uid + ' : ' + @modelname + ' : ' + notify._id
			@socket.broadcast.to(uid).emit 'push:Notification', obj

		return unless @apns

		# FIXME: Move this - it is application specific code and doesn't belong in the framework
		id = if @modelname.match /Interval|Vote/ then data.data['case'] else data.objid

		# Skip interval edits for now
		return if @modelname is 'Interval' and data.action is 'edited'

		@models.Case.model.findById id, (err, mycase) =>
			return @cmdErr err if err?

			action = switch @modelname
				when 'Vote' then 'bumped'
				when 'Interval' then 'started working on'
				else data.action

			uname = @user.firstname

			msg = "#{uname} #{action} #{mycase.title}"
			@sendAPNs uid, msg

	sendAPNs: (uid, msg) =>

		query =
			user: uid
			status: 'new'

		@db.Notification.find query, (err, notes) =>
			return @cmdErr err if err?

			# FIXME: Move this - it is application specific
			# Calculate the badge number
			map = {}
			for note in notes
				id = if note.type is 'Case' then note.objid else note.data['case']
				key = "#{id}-#{note.type}-#{note.action}"
				map[key] = 1

			cnt = 0
			for key,val of map
				cnt++

			# Send an APN to all of the user's devices
			@models.ApnToken.model.find { user: uid }, (err, tokens) =>
				return @cmdErr "Could not get APN tokens for user: #{uid}" if err?

				for token in tokens
					@logger.debug "Sending APN to user: #{uid} : #{cnt} : #{msg}"
					@apns.pushNotify token.value, msg, cnt

	# Recursively use the AccessMap to verify that a user may add this object
	checkPerms: (user, modelname, data, cb) =>
		mapval = @gmap[modelname]

		return @cmdErr 'Empty object: ' + modelname unless data

		if mapval
			mname = if mapval is true then modelname else mapval
			# FIXME: allow use of other key names beside the model name
			key = mname.toLowerCase()
			id = if mapval is true then data._id else data[key]

			opts =
				user: user._id
				type: mname
				objid: id

			#console.log 'Perm query:', opts

			@db.Right.find opts, (err, res) =>
				return cb err, null if err?

				# Found permissions
				#console.log 'Result:', res
				return cb null, true if res.length

				# Did not find permissions for this object - fetch the object itself, and continue up the map
				@models[mname].model.findById data[key], (err, obj) =>

					return cb err, null if err?

					#console.log 'Found:', mname, obj

					return cb null, false if mapval is true

					@checkPerms user, mapval, obj, cb

		else
			cb null, false

	addObject: (mname, data) =>
		# Handle Rights objects specially
		return @shareObject data if mname is 'Right'

		@logger.info 'Add: ' + mname

		mobj = @models[mname]
		model = mobj.model

		# Check for existing object
		model.findById data._id, (err, obj) =>
			return @cmdErr err if err?

			# FIXME: log this, and send extra info back to client about this being found?
			# Return existing object if found in DB already
			return @cb JSON.stringify(obj) if obj

			# Set the last edited date (used for sync)
			data.edited = new Date()

			obj = new model data
			obj.history = []

			# Initialize any new per-user fields
			for fname,val of @gschema[mname]
				if val.peruser
					obj[fname] = []

			# Add the history data to the history as 'Edit' objects
			data.history ?= []
			for hdata in data.history
				edit = new @db.Edit hdata
				obj.history.push edit

			# FIXME: need to handle any reference fields - check that IDs are valid

			# Add any auto-increment fields
			if auton = mobj.autonum
				@models[auton.modelname].model.findById data[auton.key], (err, refobj) =>
					return @cmdErr err if err?

					key = 'next' + mname + 'Id'
					return @cmdErr 'No autonum field: ' + key unless refobj[key]

					#console.log refobj, auton, key, refobj[key]
					obj[auton.field] = refobj[key]
					refobj[key] += 1
					refobj.save (err) =>
						return @cmdErr err if err?
						#console.log obj
						@saveReply 'added', data, mname, obj
			else
				@saveReply 'added', data, mname, obj

	# Save an object, clean it up, and then send it out to each user
	saveReply: (action, data, modelname, obj) =>
		obj.save (err) =>
			return @cmdErr err if err?
			@sendToAll action, data, modelname, obj, =>
				@cleanup modelname, @uid, obj
				@cb JSON.stringify(obj)

	# Share an object with another user: add a 'Right' object
	shareObject: (data) =>

		modelname = data.type

		# Confirm that the user has rights for the specified object
		@checkObject modelname, data.objid, (res) =>

			#console.log modelname, data, res

			unless res
				@logger.error "Share: User does not have rights for " + modelname + ' : ' + data.objid
				return @cb false

			# Get users with access to this object
			@getUsers modelname, [data.objid], (users) =>
				throw err if err?

				#console.log 'Existing:', users
				for uid in users
					if uid.toString() is data.user
						@logger.error "Share: User " + data.user + " already added to " + modelname + ' : ' + data.objid
						return @cb false

				@logger.info 'Share: ' + modelname + ' : ' + data.objid + ' -> ' + data.user

				# FIXME: make sure we haven't added this already ...

				# Set the last edited date (used for sync)
				data.edited = new Date()

				# Add the Rights object
				rt = new @db.Right data

				rt.history = []

				rt.save (err, obj) =>
					throw err if err?

					#console.log obj

					# Fetch the user that is being shared
					@models.User.model.findById data.user, (err, myuser) =>
						return @cmdErr 'Could not get user: ' + data.user if err? or not myuser

						#console.log 'Share user: ', myuser, '\n', users, '\n', skip
						allusers = users.map (uid) -> { _id: uid }
						allusers.push myuser

						allusers.forEach (muser) =>
							# Send a notification of the share
							ndata =
								creator: @uid
								user: muser._id
								type: modelname
								objid: data.objid
								action: 'shared'
								data:
									user: data.user

							@sendNotify muser._id, modelname, ndata unless @isCurrUser(muser._id)

						# Push the shared user info down to other users
						query = @models.User.model.find {}
						query.where('_id').in users
						query.where('_id').nin [data.user, @uid]
						query.exec (err, musers) =>
							throw err if err?

							#console.log 'Users:', musers

							# TODO: this will re-send any users already on the object ...

							musers.forEach (muser) ->
								uobj = muser.toObject()
								@cleanup 'User', muser._id, uobj
								@logger.debug 'User push: ' + muser.userid + ' : ' + uobj._id
								@socket.broadcast.to(muser._id).emit 'push:User', uobj


						# TODO: Don't bother to fetch if the user isn't connected - check the sockets

						# Push the item & any related objects to the added user - similar to bulk sync
						@getDepObjects modelname, data.objid, (idmap) =>
							for mname, ids of idmap
								continue unless ids.length

								@getAndSend myuser, mname, ids

							# All done
							@cb true

	getAndSend: (user, modelname, ids) =>
		query = @models[modelname].model.find {}
		query.where('_id').in(ids)

		query.exec (err, objs) =>
			throw err if err?

			for obj in objs
				#console.log 'sync push:', modelname, obj

				# Convert from Mongoose to regular object and cleanup fields
				obj = obj.toObject()
				@cleanup modelname, user._id, obj

				@socket.broadcast.to(user._id).emit 'push:' + modelname, obj


	# Clean up any per-user and private fields
	cleanup: (modelname, uid, obj) =>

		# Remove history from User objects
		delete obj.history if modelname is 'User'

		for key,val of @gschema[modelname]

			#console.log 'Cleanup', modelname, key, val, obj

			# Skip un-initialized fields
			continue unless obj[key]

			delete obj[key] if val['private']


			if val.peruser
				found = false
				for id in obj[key]
					found = true if id.toString() == uid.toString()
				#obj[key] = uid.toString() in obj[key]
				obj[key] = found
			#console.log modelname, uid, key, obj[key]

			# Handle embedded objects
			if val.embedded
				#console.log modelname, uid, key, val.type
				for eobj in obj[key]
					@cleanup val.type, uid, eobj

	getAllRights: (user, cb) =>
		query = @db.Right.find
			user: user._id
		query.select 'objid type'

		rights = {}
		query.exec (err, data) =>
			throw err if err?

			for obj in data
				rights[obj.type] ?= []
				rights[obj.type].push obj.objid

			cb rights

	getRights: (user, map, modelname, cb) =>

		query = @db.Right.find
			user: user._id
			type: modelname
		query.select 'objid'

		query.exec (err, data) =>
			throw err if err?
			map[modelname] = data.map (obj) -> obj.objid

			cb null, map

	# Recursively get the users that have rights to the objects of a specified type with specified IDs
	getUsers: (modelname, ids, cb) =>
		#console.log modelname, ids

		query = @db.Right.find {}
		query.select 'user'
		query.where('type').equals(modelname)
		query.where('objid').in ids

		query.exec (err, objs1) =>
			throw err if err?

			#console.log 'User objects:', objs1
			userids = objs1.map (o) -> o.user

			#console.log 'User IDs', modelname, userids

			# Follow the access map to find more IDs
			mapname = @gmap[modelname]
			if mapname and mapname != true
				# Get IDs for the mapped field name
				q = @models[modelname].model.find {}
				fname = mapname.toLowerCase()
				q.select fname
				q.where('_id').in ids
				q.exec (err, objs) =>
					throw err if err?

					newids = objs.map (o) -> o[fname]
					#console.log 'N:', fname, newids

					@getUsers mapname, newids, (userids2) =>
						#console.log 'More IDs:', mapname, userids2
						for id in userids2
							userids.push id

						#console.log 'User IDs', modelname, userids
						cb userids
			else
				cb userids

	fetchIds: (map, mname, modelname, ids, cb) =>
		keyn = modelname.toLowerCase()

		#console.log 'Q:', modelname, keyn, moreids
		query = @models[mname].model.find {}
		query.select '_id'
		query.where(keyn).in ids

		query.exec (err, mobjs) =>
			throw err if err?
			#console.log mname, mobjs

			map[mname] = mobjs.map (o) -> o._id
			cb null, map


	getDepObjIds: (user, modelname, ids, map, cb) =>
		deps = []
		for mname,refname of @gmap
			deps.push mname if refname is modelname

		#console.log deps

		func = (map, mname2, cb2) =>
			@fetchIds map, mname2, modelname, ids, cb2

		async.reduce deps, map, func, (err, res) =>
			throw err if err?

			# FIXME: need to recursively drill down through AccessMap ...

			cb res

	# Get the list of Object IDs for that are tied to an object
	getDepObjects: (modelname, id, cb) =>

		mymap = {}
		mymap[modelname] = [id]

		# Recursively go through the models using the AccessMap
		@getDepObjIds @uid, modelname, [id], mymap, (map) =>
			#console.log 'Map:', map
			cb map

	checkObject: (modelname, id, cb) =>

		# Get the rights for each model
		@getAllRights @user, (rights) =>
			#console.log 'Rights:', rights

			@getObjectIds rights, modelname, [], (ids) =>
				#console.log modelname, ids

				for myid in ids
					return cb true if myid.toString() == id.toString()

				cb false

	syncObjects: (objs) =>

		rmap = {}
		mnames = []
		# FIXME: skip embedded objects.  merge this code with the client side code that is similar.
		for mname,modelobj of @models
			mnames.push mname unless mname.match /User|CaseComment/

		# Get the rights for each model
		@getAllRights @user, (rights) =>
			#console.log 'Rights:', rights

			func = (map, modelname, cb) =>
				#console.log modelname
				@getObjectIds rights, modelname, [], (ids) =>
					#console.log modelname, ids
					rmap[modelname] = ids

					# Grab the users for these objects based on rights
					@getUsers modelname, ids, (userids) =>

						# Record the User IDs for fetching later ...
						for id in userids
							map.User.push id unless id in map.User

						#getobjs modelname, objs[modelname].existing, ids, socket, (eobjs) ->
						@getobjs modelname, objs[modelname], ids, (eobjs) =>
							#console.log modelname, eobjs
							map[modelname] = eobjs
							cb null, map

			# Get and send the list of users
			async.reduce mnames, { User: [], Right: [] }, func, (err, syncobjs) =>
				#console.log 'Sync:', syncobjs

				# Create a map of the rights that were sent from the client
				rtmap = {}
				for rt in objs.Right
					rtmap[rt.id] = rt.edited

				# Fetch the rights objects to push to the client
				oids = []
				for mname in mnames
					oids.push id for id in rmap[mname]
				#console.log 'Rights:', '\n', rmap, '\n', oids

				query = @db.Right.find {}
				query.where('objid').in oids
				query.exec (err, rights) =>
					throw err if err?

					#console.log 'R:', '\n', rights
					for rt in rights
						same = new Date(rtmap[rt._id.toString()]).getTime() == new Date(rt.edited).getTime()
						syncobjs.Right.push rt unless same

					#console.log 'Sync:', syncobjs

					# FIXME: remove dupes from the User list

					# Fetch the actual user objects now, if client doesn't have them
					@getobjs 'User', objs.User, syncobjs.User, (sobjs) =>
						syncobjs.User = sobjs
						#console.log sobjs

						# Fetch the notification objects as well
						nids = objs.Notification.map (o) -> o.id

						query = @db.Notification.find
							user: @uid
						query.where('_id').nin(nids)

						query.exec (err, nobjs) =>
							@logger.error err if err?
							syncobjs.Notification = nobjs

							# Send everything down to the client
							@sendObjs syncobjs

	sendObjs: (map) =>
		cnt = 0
		for modelname,objs of map
			#console.log modelname, ':', objs.length
			cnt += objs.length
		@logger.info 'Sync push: ' + @socket.id + ' : ' + cnt + ' objects'
		@socket.emit 'status', cnt

		for modelname,objs of map
			for obj in objs
				@sendObj modelname, obj

	sendObj: (modelname, obj) =>
		process.nextTick =>
			#logger.debug 'Sync: ' + modelname + ' : ' + obj._id
			@socket.emit 'sync:' + modelname, obj


	# FIXME: put these argument vars on a 'class' or object so they don't need to be passed around
	# Get the list of object IDs for a type that a user has access to
	getObjectIds: (rights, modelname, ids, cb) =>

		mids = rights[modelname] ? []
		mapval = @gmap[modelname]

		#console.log 'O:', modelname, ids, mapval, mids

		if mapval is true
			cb mids

		else if mapval

			@getObjectIds rights, mapval, mids, (moreids) =>

				keyn = mapval.toLowerCase()

				#console.log 'Q:', modelname, keyn, moreids
				query = @models[modelname].model.find {}
				query.select '_id'
				query.where(keyn).in moreids

				query.exec (err, mobjs) =>
					throw err if err?

					newids = mobjs.map (obj) -> obj._id

					#console.log 'N:', modelname, newids

					for id in newids
						mids.push id

					cb mids

		else
			cb ids

	getObject: (modelname, data, userid, cb) =>

		#console.log 'Model:', modelname, data
		model = @models[modelname].model
		query =
			_id: ObjectId data.id
			edited:
				$ne: data.edited

		model.findOne query, (err, obj) =>
			return @cmdErr 'Error fetching ' + modelname + ' object: ' + err if err?

			#console.log modelname, data.id, data.edited, obj
			# TODO: fetch object and compare date afterward, to make sure object ID is found?
			# Object was up-to-date, or ID was invalid
			return cb null, null unless obj

			@cleanup modelname, userid, obj

			#logger.debug 'Sync (edited): ' + modelname + ' : ' + obj._id
			#socket.emit 'sync:' + modelname, obj
			cb null, obj

	getobjs: (modelname, objs, myids, cb) =>

		#console.log 'getobjs:', modelname, objs, myids

		# TODO: A bit of a hack.  Handle any types on the server that aren't added to the client yet.
		objs ?= []

		myobjs = []
		ids = []

		# FIXME: we should receive a map in the function, not have to create it
		# Create a map of the authorized IDs for this model
		authmap = {}
		for id in myids
			authmap[id.toString()] = 1

		# Loop through each of the objects sent from the client and fetch it if the edit field doesn't match
		for data in objs

			ids.push data.id

			# Make sure the sent ID is in the authorized list
			continue unless authmap[data.id]

			# Don't bother to query and sync new or modified objects - client will push them up separately
			continue if data.edited is 'modified' or data.edited is 'new'

			myobjs.push data

		func = (obj, cb2) =>
			@getObject modelname, obj, @uid, cb2

		async.map myobjs, func, (err, sobjs) =>
			throw err if err?

			# Remove nulls from object list collected by async.map
			sobjs = sobjs.filter (o) -> o

			model = @models[modelname].model

			# Get any objects that the client doesn't have at all
			query = model.find {}
			query.where('_id').in myids
			query.where('_id').nin ids
			#console.log ids
			query.exec (err, mobjs) =>
				return @cmdErr 'Could not get objects: ' + modelname + ' : ' + err if err?
				for obj in mobjs
					continue unless obj

					# Convert from Mongoose to regular object - to allow field cleanup
					obj = obj.toObject()

					@cleanup modelname, @uid, obj

					sobjs.push obj
				#logger.debug 'Sync (new): ' + modelname + ' : ' + obj._id
				#socket.emit 'sync:' + modelname, obj

				cb sobjs

module.exports = ApiRequest
