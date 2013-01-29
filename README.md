
Description
-----------

Simple, schema-driven, synchronizing, offline-enabled, websocket-powered JavaScript framework.  It was created to make it easier to create dynamic, data-driven, multi-user web applications without having to explicitly write code to create the server API, permissions model.  

Created for a task & project management application, and is a good fit for applications where you want to maintain a full history of all object changes, but don't want to have to write any extra code to get it.  

It is currently only designed to work with Webkit browsers, which include Google Chrome, Safari for Mac OS X, iPhone, iPad, and Android browsers.  It is a good match for creating HTML5 web applications using PhoneGap/Cordova that need to work completely offline.



Technology
----------

Coffeescript
Mongoose
Web SQL
persistence.js
Backbone
socket.io


Features
--------

* Built to work with express 

* One schema file used to generate API and client + server models
    - MongoDB storage currently implemented 
	- Mongoose models created
	- Backbone model generation from schema
	- Socket.io API created from schema
* Full history of changes to objects
	- 
* Powerful business object sharing model w/ inheritance, by user ID
* Notifications built-in
	- Per-user notifications based on user rights & object changes
	- Apple Push Notification Service (APNs) integration
* Create offline-enabled applications
	- complete object synchronization via socket.io
	- data stored on the client in a Web SQL database (sqlite)

* Private attributes
* per-user attributes
 
* Online/offline hooks for UI display of status
* Hooks for displaying sync progress in UI 

* Full-text indexing of objects
* Logging
* Socket.io authentication 

* Mixins

Basic Usage
-----------

npm install syncro



Custom Usage
------------

Example code

server.coffee

main.coffee


Debugging
---------

debug switch: persistence.js
timelog()
local SQL store
sqlite3 command line
sqlite browser



API
---

* add
* edit


* list 

API Objects
-----------

User
Notification
Right
ApnToken


Object History
--------------

Edit


Examples
--------


TODO
----

* Flexible storage options for the server
  
