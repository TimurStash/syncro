Todo =
	name: 
		type: String
		required: true
	description: String

User =
	userid:
		type: String
		index: true
		required: true
	password:
		type: String
		required: true
		private: true
	token:
		type: String
		index: true
		private: true
	firstname: String
	lastname: String

@dbschema =
	schema:
		Todo: Todo
		User: User
	map: 
		Todo: true

# Export schema for node.js
unless @location
	module.exports = @dbschema
