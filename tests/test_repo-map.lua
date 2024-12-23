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
  eq(child.lua_get([[M.repoMap('deps/todomvc/examples/javascript-es6/src')]]), [[
deps/todomvc/examples/javascript-es6/src/model.js:
class Model {
    constructor(storage) {
    create(title, callback) {
    read(query, callback) {
    update(id, data, callback) {
    remove(id, callback) {
    removeAll(callback) {
    getCount(callback) {

deps/todomvc/examples/javascript-es6/src/view.js:
const ENTER_KEY = 13;
export default class View {
    constructor(template) {
    _clearCompletedButton(completedCount, visible) {
    render(viewCmd, parameter) {
    bindCallback(event, handler) {

deps/todomvc/examples/javascript-es6/src/controller.js:
class Controller {
    constructor(model, view) {
    setView(hash) {
    showAll() {
    showActive() {
    showCompleted() {
    addItem(title) {
    editItem(id) {
    editItemSave(id, title) {
    editItemCancel(id) {
    removeItem(id) {
    removeCompletedItems() {
    toggleComplete(id, completed, silent) {
    toggleAll(completed) {
    _updateCount() {
    _filter(force) {
    _updateFilter(currentPage) {

deps/todomvc/examples/javascript-es6/src/store.js:
let uniqueID = 1;
export class Store {
    constructor(name, callback) {
    find(query, callback) {
    findAll(callback) {
    save(updateData, callback, id) {
    remove(id, callback) {
    drop(callback) {

deps/todomvc/examples/javascript-es6/src/template.js:
const htmlEscapes = {
class Template {
    show(data) {
    itemCounter(activeTodos) {
    clearCompletedButton(completedTodos) {

deps/todomvc/examples/javascript-es6/src/app.js:
let todo;
function Todo(name) {

deps/todomvc/examples/javascript-es6/src/helpers.js:
const qs = (selector, scope) => {
    function dispatchEvent(event) {

]])
end

T['repoMap()']['max_tokens'] = function()
  eq(child.lua_get([[M.repoMap('deps/todomvc/examples/javascript-es6/src', 200)]]), [[
deps/todomvc/examples/javascript-es6/src/model.js:
class Model {
    constructor(storage) {
    create(title, callback) {
    read(query, callback) {
    update(id, data, callback) {
    remove(id, callback) {
    removeAll(callback) {
    getCount(callback) {

deps/todomvc/examples/javascript-es6/src/view.js:
const ENTER_KEY = 13;
export default class View {
    constructor(template) {
    _clearCompletedButton(completedCount, visible) {
    render(viewCmd, parameter) {
    bindCallback(event, handler) {

]])
end

local M = require('repo-map')
local function tmp_file_path()
  local base_filename = os.tmpname()
  local random_suffix = math.random(1000000, 9999999)
  return base_filename .. "_" .. random_suffix
end

T['Usage'] = new_set()

T['Usage']['save and load'] = function()
  local file_path = tmp_file_path()
  local usage = M.Usage:new()
  usage:count('my_method', 'my_test_file.lua')
  usage:save(file_path)
  local usageFromFile = M.Usage.load(file_path)
  eq({ ['my_method'] = 1}, usageFromFile.method_counts)
  eq({ ['my_test_file.lua']={ ['my_method']=1 } }, usageFromFile.callee_file_name_counts)
end

T['Usage']['collect_usage'] = function()
  local usage = M.Usage:new()
  local parsed = usage:parse_source('a.js', [[
    import { ba, bb }  from './b.js'
    function aa() { ba() }
    function ab() { bb() }
  ]])
  usage:collect_usage(parsed)
  parsed = usage:parse_source('b.js', [[
    function ba() {}
    function bb() { ba() }
    export { ba, bb }
  ]])
  usage:collect_usage(parsed)
  eq({
    ['a.js'] = {['ba'] = 1, ['bb'] = 1},
    ['b.js'] = {['ba'] = 1}
  },usage.callee_file_name_counts);
  eq({
    ba = 2,
    bb = 1
  }, usage.method_counts)
  eq({
    aa = {'a.js'},
    ab = {'a.js'},
    ba = {'b.js'},
    bb = {'b.js'}
  },usage.method_to_file_paths)
end

T['Usage']['collect_usage where parsed contents have changed'] = function()
  local usage = M.Usage:new()
  local parsed = usage:parse_source('a.js', [[
    import { ba, bb }  from './b.js'
    function aa() { ba() }
    function ab() { bb() }
  ]])
  usage:collect_usage(parsed)
  parsed = usage:parse_source('b.js', [[
    function ba() {}
    function bb() { ba() }
    export { ba, bb }
  ]])
  usage:collect_usage(parsed)
  local copy = vim.deepcopy(usage);

  parsed = usage:parse_source('b.js', [[
    function ba() { bb() }
    function bb() { aa() }
    export { ba, bb }
  ]])
  usage:collect_usage(parsed, copy)


  eq({
    ['a.js'] = {['ba'] = 1, ['bb'] = 1},
    ['b.js'] = {['aa'] = 1, ['ba'] = 0, ['bb'] = 1}
  },usage.callee_file_name_counts);
  eq({
    aa = 1,
    ba = 1,
    bb = 2
  }, usage.method_counts)
  eq({
    aa = {'a.js'},
    ab = {'a.js'},
    ba = {'b.js'},
    bb = {'b.js'}
  },usage.method_to_file_paths)
end

return T;
