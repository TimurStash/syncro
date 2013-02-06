###
Todo = Backbone.Model.extend(
	defaults: ->
		title: "empty todo..."
		order: Todos.nextOrder()
		done: false

	initialize: ->
		@set title: @defaults().title	unless @get("title")

	toggle: ->
		@save done: not @get("done")
)
###
class TodoList extends Backbone.Collection
	model: Todo
	done: ->
		@filter (todo) ->
			todo.get "done"

	remaining: ->
		@without.apply this, @done()

	nextOrder: ->
		return 1	unless @length
		@last().get("order") + 1

	comparator: (todo) ->
		todo.get "order"

Todos = new TodoList

class TodoView extends Backbone.View
	tagName: "li"
	template: _.template($("#item-template").html())
	events:
		"click .toggle": "toggleDone"
		"dblclick": "edit"
		"click a.destroy": "clear"
		"keypress .edit": "updateOnEnter"
		"blur .edit": "close"

	initialize: =>
		@listenTo @model, "change", @render
		@listenTo @model, "destroy", @remove

	render: =>
		@$el.html @template(@model.toJSON())
		@$el.toggleClass "done", @model.get("done") != ""
		@input = @$(".edit")
		this

	toggleDone: =>
		@model.toggle()

	edit: =>
		@$el.addClass "editing"
		@input.focus()

	close: =>
		value = @input.val()
		unless value
			@clear()
		else
			@model.save name: value
			@$el.removeClass "editing"

	updateOnEnter: (e) =>
		@close() if e.keyCode is 13

	clear: =>
		@model.destroy()

class AppView extends Backbone.View
	template: _.template($("#app-tpl").html())
	statsTemplate: _.template($("#stats-template").html())

	events:
		"keypress .new-todo": "createOnEnter"
		"click #clear-completed": "clearCompleted"
		"click #toggle-all": "toggleAllComplete"
		"click .clear-db": "clearLocalDB"

	setPending: =>

	render: =>
		@$el.html @template()
		this

	setup: =>
		@listenTo Todos, "add", @addOne
		@listenTo Todos, "reset", @addAll
		@listenTo Todos, "all", @render

		@footer = @$("footer")
		@main = $("#main")

		done = Todos.done().length
		remaining = Todos.remaining().length
		if Todos.length
			@main.show()
			@footer.show()
			@footer.html @statsTemplate
				done: done
				remaining: remaining
			
		else
			@main.hide()
			@footer.hide()

		@allCheckbox = @$(".toggle-all").get()
		@allCheckbox.checked = not remaining

	addOne: (todo) =>
		view = new TodoView model: todo
		@$("#todo-list").append view.render().el

	addAll: =>
		Todos.each @addOne, this

	createOnEnter: (e) =>
		@input = @$(".new-todo")
		return	unless e.keyCode is 13
		return	unless @input.val()
		todo = new Todo
		todo.save name: @input.val()
		@addOne todo
		@input.val ""

	clearCompleted: =>
		_.invoke Todos.done(), "destroy"
		false

	toggleAllComplete: =>
		done = @allCheckbox.checked
		Todos.each (todo) ->
			todo.save done: done

	clearLocalDB: =>
		resetApp true

List = null

$ ->

	$.cookie 'token', 'secretcode'
	startIO()

	window.App = new AppView
	$('body').append App.render().el

	Todo.prototype.fetch (todos) ->
		Todos.add todos
		App.setup()	
		App.addAll()

