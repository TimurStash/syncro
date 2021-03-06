Syncro
======

Description
-----------

Simple, schema-driven, synchronizing, offline-enabled, websocket-powered JavaScript framework with notifications & powerful access control.  

This framework was created to make it easier to create dynamic, data-driven, multi-user web applications without having to explicitly write code to create the server API, permissions model.  

The code was extracted from a task & project management application, and is a good fit for applications where you want to maintain a full history of all object changes, but don't want to have to write any extra code to get it.  

It is currently only designed to work with Webkit browsers, which include Google Chrome, Safari for Mac OS X, iPhone, iPad, and Android browsers.  It is a good match for creating HTML5 web applications using PhoneGap/Cordova that need to work completely offline.


Technology
----------

* [CoffeeScript](http://coffeescript.org/)
* [Mongoose](http://mongoosejs.com/)
* [Web SQL](http://en.wikipedia.org/wiki/Web_SQL_Database)
* [persistence.js](http://persistencejs.org/)
* [Backbone](http://backbonejs.org/)
* [socket.io](http://socket.io/)

Features
--------

* Built to work with [express](http://expressjs.com/)

* One schema file used to generate API and client + server models
    - [MongoDB](http://www.mongodb.org/) storage currently implemented 
	- [Mongoose](http://mongoosejs.com/) models created
	- [Backbone](http://backbonejs.org/) model generation from schema
	- [Socket.IO](http://socket.io/) API created from schema
	- Relationships, indexes, types, and validation
	* Private attributes
	* Per-user attributes
	* Mixins
* Simple client-side API for object creation, fetch, save, update

* Full history of changes to objects

* Powerful business object sharing model w/ inheritance, by user ID

* Notifications built-in
	- Per-user notifications based on user rights & object changes
	- [Apple Push Notification Service](http://en.wikipedia.org/wiki/Apple_Push_Notification_Service) (APNs) integration

* Create offline-enabled applications
	- complete object synchronization via socket.io
	- data stored on the client using [persistence.js](http://persistencejs.org/) to save to a [Web SQL](http://en.wikipedia.org/wiki/Web_SQL_Database) (sqlite) database

* Full two-way synchronization of objects with merge resolution hooks
    * Online/offline hooks for UI display of status
    * Hooks for displaying sync progress in UI 

* Full-text indexing & search of object fields
* Logging
* [Socket.io authorization](https://github.com/LearnBoost/socket.io/wiki/Authorizing)

Dependencies
------------

* MongoDB
* Linux or Mac OS X (due to use of symlinks)
* Redis (example app uses Redis for session store, for now)

Basic Usage
-----------

    npm install syncro

### Database Schema

Create a schema file:

```coffeescript
TodoList = 
	name: String

Todo =
	name: 
		type: String
		required: true
	description: String
	done:
		type: Boolean
	todolist: 
		type: 'TodoList'
		required: true

@dbschema =
	schema:
		Todo: Todo
		TodoList: TodoList
	map: 
		TodoList: true
		Todo: 'TodoList'

# Export schema for node.js
unless @location
	module.exports = @dbschema
```

### Create User & Objects

All API calls made by your application need to be performed by a user that can be found in the database, with rights to create & view objects.

### Create the Server

```coffeescript
express = require 'express'

dbname = 'todos'
port = 8150

app = express.createServer()

app.configure ->
	app.use express.cookieParser()
	app.use express.session
		secret: 'secretkey'
	app.use app.router
	app.use express.errorHandler
		dumpExceptions: true
		showStack: true

syncro = require 'syncro'

# FIXME: this is a hack
logger.warn = logger.warning

syncro.setLogger logger

# Connect to the Mongo database via Mongoose
syncro.db.connect 'mongodb://localhost/' + dbname

# Include the database schema
dbschema = require './schema'

# Generate the Mongoose schema, models, and socket.io API
syncro.genapi app, dbschema, redis

app.get '/', (req, res) ->
	res.render 'index.jade', { layout: false }

app.listen port

console.log 'Using database: ' + dbname
console.log 'Server running at http://127.0.0.1:' + port
```

### Create the Client app

Create a symlink to the client-side JS:

    ln -s node_modules/syncro/lib/client-min.js

Create your application:

```html
<html>
	<head>
		<script type="text/javascript" src="schema.js"></script>
		<script type="text/javascript" src="client-min.js"></script>
		<script type="text/javascript">

			// Set a cookie for the auth token, so the server will know which user is connecting
			$.cookie('token', 'secretcode');

			var todo = new Todo;
			todo.save({
				title: "My First Task",
				description: "Learn how to use this framework"
			});

		</script>
	</head>
</html>	
```

You'll probably want to replace the inline cookie code with a login form, or similar.


Schema
------

A model is defined as an object with **keys** corresponding to the field names, and **values** specifying the types.  In CoffeeScript:

```coffeescript

Car =
    make: 
    	type: String
    	required: true
    model: String
    purchased: Date
    year: Number 
```

### Types

Several [Mongoose/JavaScript types]() are supported

* **Boolean**
* **String**
* **Object**
* **Number**
* **Date** 

The **values** for the field may either be one of the types above, or an **object** with a `type` key and value (see above).

If using the **object** syntax, extra keys can be specified on the field:

* **required**: the field is required (validated by Mongoose)
* **fulltext**: index this field for full-text searching (client-side)
* **enum**: an array of values for a **String** type that the field may have
* **index**: set to `true` to index this field in the Mongo DB and the Web SQL (sqlite) DB
* **peruser**:
* **private**:

### Relationships

You may use the **object** syntax for a field to define a relationship to another model.

```coffeescript
Make =
    name: String

Car =
	make: 'Make'
	type: required
```

This will cause an index to be created in both the client & server DBs.  It will also create methods for accessing these

### Included Types

* **User**
* **Right**
* **Notification**
* **ApnToken**

### Extra Fields

* **history**
* **created**
* **creator**
* **edited**

Client API
----------

A `syncro` object is defined globally by including the `client-min.js` script in to your web page.

In addition, global objects are created for each of the models defined in your schema.  Basic CRUD operations for a `Car` model:

### Create

    var mycar = new Car();
    mycar.save({
    	make: 'Toyota',
    	model: 'Camry'
    });

### Read

   Car.find
   Car. 

### Update

```javascript
    Car.save({
    	lastwash: new Date()
    });
```

### Delete

* TBD, not implemented


History
-------

Each object created & edited with the API gets a full history of the changed to the object.  The `history` array on the object contains object in this format:

```javascript
{
	creator: ObjectId,
	created: Date,
	changes: {
		field: newvalue,
		field2: othervalue
	}
}
```

On the server, internally, a Mongoose `Edit` type is defined for the **history** objects.

Object Permissions
------------------

When defining the schema, you must specify an **access map** for your models.

Each key in the schema's `map` object is the name of a model.  

* models for which object permissions are granted directly should have a value of `true`.
* models for objects which should be accessible via a relationship, in which the user has permissions on a parent object, should use the model name of the parent object as a string.

```coffeescript
@dbschema.map =
	TodoList: true
	Todo: 'TodoList'
```

Permissions are granted via the `Right` model.  An example `Right` object:

```coffeescript
myperm =
	created: new Date()
	creator: user.id
	edited: new Date()
	user: otheruser.id
	objid: obj.id
	type: 'Todo'
	access: 'full'
```

* Only `full` permissions are available with the current version.

The client-side API lets you **share** an object with another **User**.  Behind the scenes, a `Right` object is created on the client, and synced to the server.

```coffeescript

	Todo.find { name: "Clean House" }, (todo) ->	
		User.find { name: "Alice" }, (user) ->

			# Share the Todo object with Alice
		    todo.share user
```

Notifications
-------------

Changes to any objects that are **shared** will trigger the creation of **Notification** objects on the server for all users that have **rights** to the shared object, either directly, or by chaining.

These **Notification** objects will be pushed automatically to any clients that are connected, via **socket.io**, or during **bulk sync** when a client re-connects to the server.

_Need example object, more info_


Synchronization
---------------

All model changes are full synchronized between client & server.  Individual fields can be edited on an object and changes will be synchronized without loss.

### Algorithm

The sync algorithm works as follows:

**Bulk Sync**:

* on connect to the server
	- all **ObjectId**s and **edited** dates are sent to the server
		- sent as one big array, after fetching from each DB table on the client
		- only objects that were previously saved to the server and haven't been modified
	- all **new** and **modified** objects are pushed to the server
* server gets object IDs and model types based on **user rights**
* server fetches objects, **checks history**
    - any objects that have **only new client edits** are updated on the server
    - any objects that have **only server edits** are pushed to clients
    - any objects that are changed on **both client & server**
        - if fields **do not conflict**
            - merged object is sent back down to the client
        - if fields **conflict**
            - object is sent back down to the client
            - client is responsible for merge resolution 

**Live Sync**:

* all edits on the client are pushed up to the server, and down to other connected clients
    - see alrorithm as above

The synchronization process is designed to be correct & fairly powerful, but is not implemented as efficiently as possible.  For users with access to a lot of objects that perform bulk syncs often, server load may be increased.


Logging
-------

_Needs documentation_

Custom Usage
------------

Example code

server.coffee

main.coffee

Apple Push Notifications
------------------------

To use the [Apple Push Notification Service](http://developer.apple.com/library/mac/#documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/ApplePushService/ApplePushService.html) you will need to have an active iOS Developer account with Apple, and then provision

The easiest way to use APNs is to build an HTML5 web application using Syncro, and wrap it up using [PhoneGap](http://phonegap.com/).  The easiest way is probably using the [Cordova PushNotification Plugin](https://github.com/phonegap/phonegap-plugins/tree/master/iOS/PushNotification).

To enable push notifications on the server, you will need to add a `[apns]` section to your `config.ini` file, with the paths for your private key & APNS certificate:

```ini
[apns]

cert = ../ssl/dev-apn.crt
key = ../ssl/dev-apn.key
gateway = gateway.sandbox.push.apple.com
```

_Need example client-side code_


Debugging
---------

TODO: Add info on:

* debug switch: persistence.js
* timelog()
* db querying commands

### Web SQL store

In Google Chrome, you can typically find the SQLite database here:

* **Linux**: `~/.config/google-chrome/Default/databases/http(s)_<host>_<port>`
* **Mac OS X**:
* **Windows**
    - **Windows XP**: 
    - **Windows Vista, 7, 8**:

To view the database:

* sqlite3 command line

    sqlite3 <dbname>

* sqlite browser



Server API
----------

For most applications, you should not need to access the server API directly.  For each model, a **socket.io** listener is created for **add**, **edit**, and **list**.

* `add:<modelname>`
* `edit:<modelname>`
* `list:<modelname>`

The bulk sync API is accessed via the `sync` event.

Tests
-----

Tests are run by mocha:

    make test

Examples
--------

Example applications can be found here: https://github.com/mkopala/syncro-examples

* [Todos](https://github.com/mkopala/syncro-examples/tree/master/todos)

TODO
----

* Flexible storage options for the server (MySQL)
* replace persistence.js
* use of both backbone and persistence.js is ugly and messy
* split in to multiple modules
* rewrite of the ugly & inefficient client-side model generation code 
* convert to IcedCoffeeScript

Disclaimer
----------

I'm aware that there is a lot to improve & cleanup with this module.  

It's basically a bunch of duct tape to hold Backbone, persistence.js, and Mongoose together.  The dependencies & code to glue them together are quite ugly for now.

This was extracted from my first project w/ node.js & coffeescript.  Some of the code is pretty bad.  My JavaScript skills aren't the best.  But it works, at least for me, and that has been the most important thing so far.

License
-------

The MIT License

Copyright (c) 2012-2013 Matt Kopala, https://github.com/mkopala

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
