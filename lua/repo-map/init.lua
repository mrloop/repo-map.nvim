local ts = vim.treesitter;

local M = {}

local gitignore_patterns = nil

local function get_git_root()
  local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
  if git_root == nil or git_root == "" then
    return nil -- Not a Git repository
  end
  return git_root
end

local function load_gitignore_file(filepath)
  local patterns = {}

  local stat = vim.loop.fs_stat(filepath)
  if not stat then
    return patterns
  end

  local file = io.open(filepath, "r")
  if not file then
    return patterns
  end

  for line in file:lines() do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if not line:match("^#") and line ~= "" then
      line = line:gsub("%*", ".*")
      table.insert(patterns, line)
    end
  end

  file:close()
  return patterns
end

local function load_gitignore_patterns()
  local patterns = {}

  local git_root = get_git_root()
  if git_root then
    local local_gitignore = git_root .. "/.gitignore"
    local local_patterns = load_gitignore_file(local_gitignore)
    vim.list_extend(patterns, local_patterns)
  end

  local global_gitignore_path = vim.fn.systemlist("git config --get core.excludesFile")[1]
  if global_gitignore_path == nil or global_gitignore_path == "" then
    global_gitignore_path = vim.fn.expand("~/.gitignore_global")
  end

  local global_patterns = load_gitignore_file(global_gitignore_path)
  vim.list_extend(patterns, global_patterns)

  return patterns
end

local function is_file_in_gitignore(filename)
  if not gitignore_patterns then
    gitignore_patterns = load_gitignore_patterns()
  end

  for _, pattern in ipairs(gitignore_patterns) do
    if filename:match(pattern) then
      return true
    end
  end

  return false
end

local function iterate_file_paths_in_dir(directory, callback, path)
  path = path or ''
  local current_path = directory .. path
  local handle = vim.loop.fs_scandir(vim.fn.expand(current_path))
  if not handle then return end

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then break end

    local relative_path = path .. '/' .. name
    if not is_file_in_gitignore(relative_path) then
      if type == 'directory' and name ~= '.git' then
        -- Recursively iterate through the subdirectory
        iterate_file_paths_in_dir(directory, callback, relative_path)
      elseif type == 'file' then
        -- Process the file (e.g., print the file path)
        callback(directory .. relative_path)
      end
    end
  end
end

local function array_contains(arr, val)
  for i = 1, #arr do
    if arr[i] == val then
      return true
    end
  end
  return false
end

local function getFileModificationTime(filePath)
  local f = assert(io.popen("stat -c %Y " .. filePath, "r"))
  local lastModified = f:read("*number")
  f:close()
  return lastModified;
end

local function open_file(file_path)
  local file = io.open(file_path, 'r')
  if not file then
    error('Could not open file: ' .. file_path)
  end
  local source = file:read('*all')
  file:close()
  return source
end

-- Function to split a string by a specified separator and handle empty lines
local function split(inputstr, sep)
  local t = {}
  local start_pos = 1
  local sep_len = #sep

  while true do
    local sep_start, sep_end = inputstr:find(sep, start_pos, true)
    if not sep_start then
      -- No more separators, add the last segment
      table.insert(t, inputstr:sub(start_pos))
      break
    end
    -- Add segment before the separator
    table.insert(t, inputstr:sub(start_pos, sep_start - 1))
    -- Move start position past the separator
    start_pos = sep_end + 1
  end

  -- Handle trailing empty line if the string ends with a separator
  if inputstr:sub(-sep_len) == sep then
    table.insert(t, "")
  end

  return t
end

local function get_text(nodes, source)
  if nodes[1] then
    local start_row, _, end_row = nodes[1]:range()
    for _, node in ipairs(nodes) do
      local node_start_row, _, node_end_row = node:range()
      if start_row > node_start_row then
        start_row = node_start_row
      end
      if end_row < node_end_row then
        end_row = node_end_row
      end
    end

    local source_lines = split(source, "\n")
    local output = ''
    for i = start_row, end_row do
      if i == start_row then
        output = source_lines[i+1]
      else
        output = output .. '\n' .. source_lines[i+1]
      end
    end
    return output;
  end
  return nil
end

-- Function to recursively traverse and print the desired nodes
-- http://neovim.io/doc/user/treesitter.html#treesitter-node
-- https://github.com/tree-sitter/tree-sitter
local function print_info(node, source, context)
  context = context or {}

  local node_type = node:type()
  local output = '';

  local nodes = {};

  if node_type == 'class_declaration' then
    nodes = {node:field('name')[1]}
    context.in_class = true;

  elseif node_type == 'field_definition' then
    nodes = {node:field('property')[1], node:field('value')[1]}

  elseif node_type == 'function_declaration' then
    nodes = {node:field('name')[1], node:field('parameters')[1]}
    context.in_function = true;

  elseif node_type == 'method_definition' then
    nodes = {node:field('name')[1], node:field('parameters')[1]}
    context.in_method = true;

  elseif node_type == 'variable_declarator' and not context.in_function and not context.in_method and not context.in_variable then
    nodes = {node:field('name')[1]}
    context.in_variable = true;
  end

  local text = get_text(nodes, source)
  if text then
    output = output .. text .. '\n'
  end

  -- Recursively print child nodes
  for child in node:iter_children() do
    output = output .. print_info(child, source, context)
  end
  return output;
end

local query_string = [[
  (method_definition name: (property_identifier) @method_name)
  (function_declaration name: (identifier) @function_name)
  (call_expression function: (identifier) @method_call)
  (call_expression function: (member_expression property: (property_identifier) @method_call))
]]

local function find_first_parent(node, type)
  -- Traverse the AST upwards
  while node do
    -- Check if the node type is 'class_declaration'
    if node:type() == type then
      return node
    end
    node = node:parent()
  end
  return nil
end

local function sort_by_field(tbl, field)
  local keys = {}
  for key in pairs(tbl) do
    table.insert(keys, key)
  end

  -- Sort the keys based on the field in the associated value
  table.sort(keys, function(a, b)
    if tbl[a][field] == tbl[b][field] then
      return a < b -- fallback to Lexicographical comparison of keys if fields are equal
    else
      return tbl[a][field] > tbl[b][field]
    end
  end)

  -- Iterator function
  local i = 0
  return function()
    i = i + 1
    if i <= #keys then
      local key = keys[i]
      return key, tbl[key]
    end
  end
end

local TOKENS_PER_WORD_ESTIMATE = 2;

local function estimate_tokens(source)
  local count = 0
  for _ in string.gmatch(source, "[^%s,()%[%]]+") do
    count = count + 1
  end
  return count * TOKENS_PER_WORD_ESTIMATE;
end

local Usage = {}

local function collect_usage_for(dirpath, usage)
  local copy = vim.deepcopy(usage);
  iterate_file_paths_in_dir(dirpath, function(file_path)
    local modified = getFileModificationTime(file_path);
    if usage:modified(file_path) ~= modified then
      local source = open_file(file_path)
      local parsed = usage:parse_source(file_path, source)
      if parsed and parsed.node then
        parsed.modified = modified
        usage:collect_usage(parsed, copy)
      end
    end
  end)
  return usage;
end

local function print_usage(usage, max_tokens)
  local output = '';
  local estimated_token_total = 0;
  for file_path in sort_by_field(usage.file_paths, 'methods_per_byte') do
    local source = open_file(file_path)
    local parsed = usage:parse_source(file_path, source)
    if parsed and parsed.node then
      local new_output = file_path .. ':\n' .. print_info(parsed.node, parsed.source) .. '\n'
      estimated_token_total = estimated_token_total + estimate_tokens(new_output)
      if max_tokens and estimated_token_total > max_tokens then
        return output
      end
      output = output .. new_output
    end
  end

  return output;
end

local function repoMap(dirpath, max_tokens)
  local cache_file_path = dirpath .. '/.repo-map-cache'

  local usage = Usage:new();
  if vim.loop.fs_stat(cache_file_path) then
    usage = Usage.load(cache_file_path)
  end

  usage = collect_usage_for(dirpath, usage)

  usage:save(cache_file_path)

  local output = print_usage(usage, max_tokens)
  return output;
end

function Usage:new()
  local o = {
    dont_parse = {},
    method_counts = {},
    -- {
    --   [method_name] = value
    -- },
    callee_file_name_counts = {},
    -- {
    --   [callee_file_name] = { [method_name]: value }
    -- }
    file_paths = { }, --  where method defined - { [file_path] = { methods = [], size = number, usage = number of methods call made  } }
    method_to_file_paths = { }, -- lookup table
  }
  setmetatable(o, self)
  self.__index = self
  return o;
end

function Usage:process_file(file_path)
  local parsed = self:parse_source(file_path)
  if parsed and parsed.node then
    print(print_info(parsed.node, parsed.source))
  end
end

function Usage:collect_usage(parsed, usage_copy)
  -- we need to know old cache state before we start updating it
  -- this is in usage_copy
  if not array_contains(self.dont_parse, parsed.language) then
    local ok, query = pcall(ts.query.parse, parsed.language, query_string)

    if ok then
      -- remove usage_copy values for this file from usage
      if usage_copy and parsed.file_path then
        for method_name, count in pairs(usage_copy.callee_file_name_counts[parsed.file_path]) do
          self:count_reverse(method_name, parsed.file_path, count)
        end
      end

      -- add new values
      for id, node, _ in query:iter_captures(parsed.node, parsed.source, 0, -1) do
        local method_name = ts.get_node_text(node, parsed.source)
        local capture_name = query.captures[id]

        if capture_name == "method_name" or capture_name == "function_name" then
          self:add_method(method_name, parsed)
        elseif capture_name == "function_call" or capture_name == "method_call" then
          self:count(method_name, parsed.file_path)
        end
      end
    else
      -- TODO handle failed parse due to invalid syntax
      table.insert(self.dont_parse, parsed.language)
    end
  end
end

function Usage:parse_source(file_path, source)
  local language = vim.filetype.match({ filename = file_path })
  if language and not array_contains(self.dont_parse, language) then
    local ok, parser = pcall(ts.get_string_parser, source, language);
    if ok then
      local tree = parser:parse()[1]
      local node = tree:root()
      return { node = node, source = source, language = language, file_path = file_path };
    else
      table.insert(self.dont_parse, language);
    end
  end
end

function Usage:_update_count(method_name, callee_file_path, value)
  value = value or 1
  if not self.method_counts[method_name] then
    self.method_counts[method_name] = 0
  end
  if not self.callee_file_name_counts[callee_file_path] then
    self.callee_file_name_counts[callee_file_path] = {}
  end
  if not self.callee_file_name_counts[callee_file_path][method_name] then
    self.callee_file_name_counts[callee_file_path][method_name] = 0
  end
  self.method_counts[method_name] = self.method_counts[method_name] + value
  self.callee_file_name_counts[callee_file_path][method_name] = self.callee_file_name_counts[callee_file_path][method_name] + value
end

-- @usage_copy old copy used to remove cached value before adding count back
function Usage:count (method_name, callee_file_path)
  self:_update_count(method_name, callee_file_path)
  local file_paths = self.method_to_file_paths[method_name];
  self:update_record_for_file_paths(file_paths, function (record)
    record.usage = record.usage + 1
  end)
end

function Usage:count_reverse(method_name, callee_file_path, count)
  self:_update_count(method_name, callee_file_path, -count)
  self:update_record_for_file_paths({callee_file_path}, function (record)
    record.usage = record.usage - count
  end)
end

function Usage:update_record_for_file_paths(file_paths, fn)
  if file_paths then
    for _, file_path in ipairs(file_paths) do
      local record = self.file_paths[file_path]
      if record then
        fn(record)
        record.methods_per_byte = record.usage / record.size
      end
    end
  end
end

-- @usage_copy old copy used to remove cached value before adding method back
function Usage:add_method (method_name, parsed)
  local file_path = parsed.file_path;
  if not self.method_to_file_paths[method_name] then
    self.method_to_file_paths[method_name] = {file_path}
  elseif not array_contains(self.method_to_file_paths[method_name], file_path) then
    self.method_to_file_paths[method_name][#self.method_to_file_paths[method_name] + 1] = file_path
  end

  local total_count = self.method_counts[method_name] or 0
  if not self.file_paths[file_path] then
    local size = string.len(parsed.source)
    self.file_paths[file_path] = {
      file_path = file_path,
      methods = {},
      methods_per_byte = total_count / size,
      size = size,
      usage = total_count,
    }
  end
  self.file_paths[file_path].methods[#self.file_paths[file_path].methods + 1] = method_name
  self.file_paths[file_path].usage = self.file_paths[file_path].usage + total_count
  self.file_paths[file_path].methods_per_byte = self.file_paths[file_path].usage / self.file_paths[file_path].size
  self.file_paths[file_path].modified = parsed.modified
end

function Usage:modified(file_path)
  if self.file_paths[file_path] then
    return self.file_paths[file_path].modified
  end
end

function Usage:serialize(indent)
  indent = indent or ""
  local result = "{\n"
  local nextIndent = indent .. "  "

  for k, v in pairs(self) do
    -- Skip the metatable to avoid serializing class metadata
    if k ~= "__index" then
      local key
      if type(k) == "string" then
        key = string.format("[%q]", k)
      else
        key = "[" .. tostring(k) .. "]"
      end

      local value
      if type(v) == "table" then
        value = Usage.serialize(v, nextIndent)
      elseif type(v) == "string" then
        value = string.format("%q", v)
      else
        value = tostring(v)
      end

      result = result .. nextIndent .. key .. " = " .. value .. ",\n"
    end
  end

  result = result .. indent .. "}"
  return result
end

function Usage:deserialize (data)
  local fnc, err = load('return' .. data);
  if not fnc then
    error("Failed to deserialize Usage: " .. err);
  end
  return fnc();
end

-- Usage.load('my_file_path');
function Usage.load(file_path)
  local usage = Usage:new();
  local file = io.open(file_path, 'r')
  if file then
    local data = file:read('*all')
    file:close();
    local result = usage:deserialize(data);
    usage.method_counts = result.method_counts;
    usage.callee_file_name_counts = result.callee_file_name_counts;
    usage.file_paths = result.file_paths;
    usage.method_to_file_paths = {}
  end
  return usage;
end

function Usage:save(file_path)
  local data = self:serialize();
  local file = io.open(file_path, 'w')
  if file then
    file:write(data)
    file:close()
  end
end

return {
  repoMap = repoMap,
  Usage = Usage,
}
