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

]])

end

return T;
