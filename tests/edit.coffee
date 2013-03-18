setup = require('./setup')
chai = require 'chai'


describe 'edit:', ->
	#Query for getting notification object
	query = {_id : new setup.ObjectID "51471cbf38d4487030000001"}

	#trying to get the object from the DB
	it "should get the object from DB", (done) ->
		#Get the object from the DB
		setup.fetchOne 'notifications',query , (err, notification) ->
			#We should get the object
			notification.should.be.instanceof Object, "fetchOne method for notifications returned not the object"

			#Check that we got exactly object as expected
			notification._id.should.be.eql query._id

			#Here we change the status of notification
			notification.status = "viewed"

			#Fire the edit event
			setup.emit 'edit:Notification', notification, (resp) ->

				#respon should to be string
				resp.should.to.be.a 'string', "edit:Notification returned unexpected responce"

				notification = JSON.parse resp

				#We should get the object
				notification.should.be.instanceof Object, "edit:Notification returned something wrong not the object"

				#The object should be exactly the same that we edited
				notification._id.should.eql query._id.toString()
				done()

	#check was the object saved to DB properly or not
	it "the 'status' property should be equal to 'viewed'", (done) ->
		setup.fetchOne 'notifications',query , (err, notification) ->
			#We should get the object
			notification.should.be.instanceof Object

			#check again that we got the object that expected
			notification._id.should.be.eql query._id

			#Check that the 'status' property was saved successfully to 'viewed'
			notification.status.should.be.equal "viewed"
			done()

