#= require '../vendor/underscore'
#= require '../vendor/backbone'
#= require '../vendor/jquery.cookie'
#= require '../vendor/async'
#= require '../vendor/moment'
#= require '../vendor/persistence'
#= require '../vendor/persistence.store.sql'
#= require '../vendor/persistence.store.websql'
#= require '../vendor/persistence.search'
#= require '../vendor/ObjectId'
#= require '../src/Base'
#= require '../src/BaseList'
#= require '../src/sync'
#= require '../vendor/socket.io'

window.syncro = new Syncro()
syncro.init()
