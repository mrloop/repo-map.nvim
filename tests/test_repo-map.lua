-- Define helper aliases
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality

-- Create (but not start) child Neovim object
local child = MiniTest.new_child_neovim()

-- Define main test set of this file
local T = new_set({
  -- Register hooks
  hooks = {
    -- This will be executed before every (even nested) case
    pre_case = function()
      -- Restart child process with custom 'init.lua' script
      child.restart({ '-u', 'scripts/minimal_init.lua' })
      -- Load tested plugin
      child.lua([[M = require('repo-map')]])
    end,
    -- This will be executed one after all tests from this set are finished
    post_once = child.stop,
  },
})

T['repoMap()'] = new_set()

T['repoMap()']['works'] = function()
  -- Execute Lua code inside child process, get its result and compare with expected result
  eq(child.lua_get([[M.repoMap('deps/todomvc/examples/javascript-es6/src')]]), [[deps/todomvc/examples/javascript-es6/src/app.js:
Variable: todo
Function: Todo((name))

deps/todomvc/examples/javascript-es6/src/controller.js:
Class: Controller
  Method: constructor((model, view))
  Method: setView((hash))
  Method: showAll(())
  Method: showActive(())
  Method: showCompleted(())
  Method: addItem((title))
  Method: editItem((id))
  Method: editItemSave((id, title))
  Method: editItemCancel((id))
  Method: removeItem((id))
  Method: removeCompletedItems(())
  Method: toggleComplete((id, completed, silent))
  Method: toggleAll((completed))
  Method: _updateCount(())
  Method: _filter((force))
  Method: _updateFilter((currentPage))

deps/todomvc/examples/javascript-es6/src/helpers.js:
Variable: qs
Function: dispatchEvent((event))

deps/todomvc/examples/javascript-es6/src/model.js:
Class: Model
  Method: constructor((storage))
  Method: create((title, callback))
  Method: read((query, callback))
  Method: update((id, data, callback))
  Method: remove((id, callback))
  Method: removeAll((callback))
  Method: getCount((callback))

deps/todomvc/examples/javascript-es6/src/store.js:
Variable: uniqueID
Class: Store
  Method: constructor((name, callback))
  Method: find((query, callback))
  Method: findAll((callback))
  Method: save((updateData, callback, id))
  Method: remove((id, callback))
  Method: drop((callback))

deps/todomvc/examples/javascript-es6/src/template.js:
Variable: htmlEscapes
Class: Template
  Method: show((data))
  Method: itemCounter((activeTodos))
  Method: clearCompletedButton((completedTodos))

deps/todomvc/examples/javascript-es6/src/view.js:
Variable: ENTER_KEY
Class: View
  Method: constructor((template))
  Method: _clearCompletedButton((completedCount, visible))
  Method: render((viewCmd, parameter))
  Method: bindCallback((event, handler))

]])

end

return T;
