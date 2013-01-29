genObjectId = ->
	increment = 0;
	pid = Math.floor(Math.random() * (32767));
	machine = Math.floor(Math.random() * (16777216));

	mongoMachineId = parseInt(localStorage['mongoMachineId'])
	if (mongoMachineId >= 0 && mongoMachineId <= 16777215)
		machine = Math.floor(localStorage['mongoMachineId']);
	localStorage['mongoMachineId'] = machine;

	return () ->
		if (!(this instanceof ObjectId))
			return new ObjectId(arguments[0], arguments[1], arguments[2], arguments[3]).toString();

		if (typeof (arguments[0]) == 'object')
			@timestamp = arguments[0].timestamp
			@machine = arguments[0].machine
			@pid = arguments[0].pid
			@increment = arguments[0].increment

		else if (typeof (arguments[0]) == 'string' && arguments[0].length == 24)
			@timestamp = Number('0x' + arguments[0].substr(0, 8))
			@machine = Number('0x' + arguments[0].substr(8, 6))
			@pid = Number('0x' + arguments[0].substr(14, 4))
			@increment = Number('0x' + arguments[0].substr(18, 6))

		else if (arguments.length == 4 && arguments[0] != null)
			@timestamp = arguments[0];
			@machine = arguments[1];
			@pid = arguments[2];
			@increment = arguments[3];

		else
			@timestamp = Math.floor(new Date().valueOf() / 1000);
			@machine = machine;
			@pid = pid;
			if (increment > 0xffffff)
				increment = 0

		@increment = increment++

window.ObjectId = genObjectId()

ObjectId.prototype.getDate = ->
	new Date(@timestamp * 1000)

ObjectId.prototype.toString = ->
	timestamp = @timestamp.toString(16)
	machine = @machine.toString(16)
	pid = @pid.toString(16)
	increment = @increment.toString(16)
	return '00000000'.substr(0, 6 - timestamp.length) + timestamp +
	'000000'.substr(0, 6 - machine.length) + machine +
	'0000'.substr(0, 4 - pid.length) + pid +
	'000000'.substr(0, 6 - increment.length) + increment
