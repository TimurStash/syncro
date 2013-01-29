class TodoApp extends Backbone.View
	template: _.template($('#app-tpl').html())

	render: =>
		$(@el).html @template()
		this

	setPending: ->

class TodoView extends Backbone.View
	template: _.template($('#todo-tpl').html())

	render: =>
		$(@el).html @template @model.toJSON()
		this

$ ->
	$.cookie 'token', 'secretcode'
	startIO()
	window.App = new TodoApp()
	$('body').append App.render().el