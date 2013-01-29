mongoose = require 'mongoose'
Schema = mongoose.Schema
ObjectId = Schema.ObjectId

models = {}

# TODO: restore use of ChangeSchema for validation purposes if possible - don't want extra _id field though ...
EditSchema = new Schema
	creator: ObjectId
	created:
		type: Date
		default: Date.now
	changes: Schema.Types.Mixed

Edit =   mongoose.model 'Edit',   EditSchema

addRight = (schema) ->
	schema.Right =
		created:
			type: Date
			default: Date.now
		creator: ObjectId
		edited:
			type: Date
			default: Date.now
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

	schema.Notification =
		created:
			type: Date
			default: Date.now
		edited:
			type: Date
			default: Date.now
		user:
			type: ObjectId
			index: true
			required: true
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
			default: "new"
			enum: ["new", "viewed"]
			required: true
		action:
			type: String
			enum: ["added", "edited", "shared"]
			required: true
		data: Object

	schema.ApnToken =
		created:
			type: Date
			default: Date.now
		user:
			type: ObjectId
			index: true
			required: true
		value:
			type: String
			index:
				unique: true
			required: true


schemas = {}
autonum = []
embed = []
embedded = {}
smap = {}

addtype = (mname, myschema, key, val) ->

	# FIXME: more advanced handling & validation needed here
	# Per-user array of types
	if val.peruser
		myschema[key] = Schema.Types.Mixed

	# Value is an array of ObjectIds or Embedded object lists
	else if val instanceof Array or val.embedded
		if val.embedded
			embedded[val.type] = 1
			embed.push
					model: mname
					key: key
					type: val.type
		else
			myschema[key] = [ObjectId]

	# Value is another type
	else if smap[val] or (val.type and smap[val.type])
		myschema[key] =
			type: ObjectId

		myschema[key].required = true if val.required

	# Mixed type
	else if val is Object
		myschema[key] = Schema.Types.Mixed

	# Auto-increment fields
	else if val.autonum
		myschema[key] = Number
		#refname = smap[val.autonum]
		models[mname].autonum =
			field: key
			modelname: val.autonum
			key: val.key
		autonum.push
				model: val.autonum
				refmodel: mname

	# Direct translation to Mongoose
	else
		myschema[key] = val

# TODO: clean this function up a bit & reduce the number of for loops
# Generate the Mongoose schema from the DB schema
genschema = (db, logger) ->

	addRight db.schema

	# Create a reverse map from the db schema
	for key,val of db.schema
		smap[key] = true

	for mname,mschema of db.schema
		myschema =
			created:
				type: Date
				default: Date.now

		# Don't keep a history for notifications
		unless mname is 'Notification'
			myschema.history = [EditSchema]

		models[mname] =
			types: {}

		# Generate the generic schema object
		for key,val of mschema
			# Skip derived types here for now
			continue if val.derived or key is 'indexes'

			#console.log key, val, typeof val
			addtype mname, myschema, key, val

		schemas[mname] = myschema

	#console.log '==> Schema: ' + mname
	#console.log myschema
	#console.log '--> Schema: ' + mname

	# Add the mixins
	#for fname,mixin in db.mixins
	#	for mname in mixin.models
	#		addtype mname, schemas[mname], fname, mixin

	# Add the auto-increment values to the parent objects
	for auton in autonum
		#console.log auton
		schemas[auton.model]['next' + auton.refmodel + 'Id'] =
			type: Number
			default: 1
			index: true

	for mname,mschema of db.schema
		# Add 'creator' field to all objects
		schemas[mname].creator = ObjectId

		# Add 'edited' field to any schemas that aren't embedded
		continue if embedded[mname]
		schemas[mname].edited =
			type: Date
			index: true

	# Create the Mongoose schemas
	dbschemas = {}
	for mname,myschema of schemas
		dbschemas[mname] = new Schema myschema

	# Embedded documents
	for eobj in embed
		newfield = {}
		newfield[eobj.key] = [dbschemas[eobj.val]]
		dbschemas[eobj.model].add newfield

		# Type map for model function lookup during API calls
		models[eobj.model].types[eobj.key] = eobj.type

	# Create the Mongoose models
	for mname,myschema of schemas
		models[mname].model = mongoose.model mname, dbschemas[mname]
		#models[mname].schema = dbschemas[mname]
		logger.debug 'Moogoose model: ' + mname

	return models

module.exports =
	genschema: genschema
	Edit: Edit
