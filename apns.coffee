# Apple Push Notifications

apns = require 'apn'
ini = require 'node-ini'

cfg = ini.parseSync '../config.ini'

apnError = (err, notify) ->
	# FIXME: use the application logger
	console.log err, notify

# Options: certificate, key, gateway, error handler
options = cfg.apns
options.errorCallback = apnError

# Apple Push Notificiation service connection
apnsConn = new apns.Connection options

# Push a notification to a device by token
exports.pushNotify = (token, message, badge = 0) ->
	note = new apns.Notification()

	device = new apns.Device(token)

	note.expiry = Math.floor(Date.now() / 1000) + 3600      # Expires 1 hour from now.
	note.badge = badge
	note.sound = "ping.aiff";
	note.alert = message
	#note.payload = {'messageFrom': 'Caroline'};
	note.device = device

	apnsConn.sendNotification(note)

