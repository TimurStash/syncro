assert = require 'assert'
sinon = require 'sinon'

ApiRequest = require '../api'

socket =
	handshake:
		user:
			_id: 1234

dbschema =
	schema:
		Right: 1
	map: 1


models =
	Right: 1
	Notification: 1
	ApnToken: 1
	Edit: ->

logger =
	info: ->

class fakemodel
	@findById: ->

describe 'addObject()', ->

	req = {}

	describe "when the modelname is 'Right'", ->

		it "should call shareObject()", (done) ->
			ApiRequest.setData dbschema, models
			req = new ApiRequest socket

			sinon.stub req, 'shareObject', (obj) ->
				done()

			data = { stuff: 1 }
			req.addObject 'Right', data

	describe 'when the object exists', ->
		beforeEach ->
			models.House =
				model:
					findById: ->
						done()

			ApiRequest.setData dbschema, models, logger
			req = new ApiRequest socket

		it "should check for an existing object with the '_id'", (done) ->

			# Stubs
			byid = sinon.stub models.House.model, 'findById', ->
				done()

			sinon.stub req, 'shareObject'
			sinon.stub logger, 'info'

			req.addObject 'House',
				_id: 4567

			assert byid.calledOnce
			assert byid.calledWith 4567

		it "should call the callback function if object exists", (done) ->

			obj =
				a: 1
				b: 2

			# Stubs
			sinon.stub models.House.model, 'findById', (id, cb) ->
				cb null, obj

			rcb = sinon.stub req, 'cb', ->
				done()

			req.addObject 'House',
				_id: 7899

			assert rcb.calledOnce
			assert rcb.calledWith JSON.stringify(obj)

	describe 'when creating a new object', ->
		beforeEach ->

			dbschema =
				schema:
					House:
						mailbox:
							type: String
							peruser: true

			models.House =
				model: fakemodel

			ApiRequest.setData dbschema, models, logger
			req = new ApiRequest socket

			# Stubs
			sinon.stub models.House.model, 'findById', (id, cb) ->
				cb null, null

		it "should initialize the per-user fields", (done) ->

			sinon.stub req, 'saveReply', (action, data, modelname, obj) ->
				assert obj.mailbox instanceof Array
				assert obj.mailbox.length == 0
				done()

			req.addObject 'House',
				history: []


		# create a history object

		# object to save contains desired props

		# edited date set to current date

	# error if autonum field doesn't exist on source object

	# referenced object is saved for autonum

	# logging
	#it "should log"

