setup = require('./setup')

sinon = require 'sinon'
chai = require 'chai'
should = chai.should()
sinonChai = require 'sinon-chai'
chai.use sinonChai

# Start the express server and connect the sockets
before (done) ->
	setup.start done

describe 'add:', ->

	it "should return the object in a callback", (done) ->

		data =
			_id: "50a7fad0e66edd27b0000004"
			name: 'Bob'
			history: [
				changes:
					name: 'Bob'
			]

		log = setup.logger()

		setup.emit 'add:Student', data, (resp) ->
			obj = JSON.parse resp

			# Assertions
			obj._id.should.equal data._id
			obj.name.should.equal data.name

			# Logging
			log.info.should.have.been.calledWith 'Add: Student'

			# TODO: need rights for this to be triggered
			uid = "50a8a033e66edd27b0000005"
			#log.debug.should.have.been.calledWith "Push: #{uid} : Student : #{data._id}"

			# TODO: need a 'fetchOne' method
			setup.fetch 'students', (objs) ->

				student = objs[0]

				#student.should.eql data
				student.name.should.equal data.name

				done()

