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

local dont_parse = {};

local function parse_file(file_path)
  local file = io.open(file_path, 'r')
  if not file then
    error('Could not open file: ' .. file_path)
  end
  local source = file:read('*all')
  file:close()

  local language = vim.filetype.match({ filename = file_path })
  if language and not array_contains(dont_parse, language) then
    local ok, parser = pcall(ts.get_string_parser, source, language);
    if ok then
      local tree = parser:parse()[1]
      local node = tree:root()
      return { node = node, source = source, language = language, file_path = file_path, modified = getFileModificationTime(file_path) };
    else
      table.insert(dont_parse, language);
    end
  end
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

local function process_file(file_path)
  local parsed = parse_file(file_path)
  if parsed and parsed.node then
    print(print_info(parsed.node, parsed.source))
  end
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

local function collect_usage(parsed, usage)
  if not array_contains(dont_parse, parsed.language) then
    local ok, query = pcall(ts.query.parse, parsed.language, query_string)

    if ok then
      for id, node, _ in query:iter_captures(parsed.node, parsed.source, 0, -1) do
        local method_name = ts.get_node_text(node, parsed.source)
        local capture_name = query.captures[id]

        if capture_name == "method_name" then
          usage:add_method(method_name, parsed)
        elseif capture_name == "function_call" or capture_name == "method_call" then
          usage:count(method_name)
         end
       end
    else
      table.insert(dont_parse, parsed.language)
    end
  end
end

local function sort_by_field(tbl, field)
  local keys = {}
  for key in pairs(tbl) do
    table.insert(keys, key)
  end

  -- Sort the keys based on the field in the associated value
  table.sort(keys, function(a, b)
    return tbl[a][field] > tbl[b][field]
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

function M.repoMap(dirpath, max_tokens)
  local usage = Usage:new();
  iterate_file_paths_in_dir(dirpath, function(file_path)
    local parsed = parse_file(file_path)
    if parsed and parsed.node then
      collect_usage(parsed, usage)
    end
  end)

  local output = '';
  local estimated_token_total = 0;
  for file_path in sort_by_field(usage.file_paths, 'methods_per_byte') do
    local parsed = parse_file(file_path)
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

Usage = {}

function Usage:new()
  local o = {
    counts = {},
    -- default nil to collect yet to be seen classes / methods
    file_paths = { },
    method_to_file_paths = { },
  }
  setmetatable(o, self)
  self.__index = self
  return o;
end

function Usage:count (method_name)
  self.counts[method_name] = (self.counts[method_name] or 0) + 1
  local file_paths = self.method_to_file_paths[method_name];

  if file_paths then
    for _, file_path in ipairs(file_paths) do
      local record = self.file_paths[file_path]
      record.usage = record.usage + 1
      record.methods_per_byte = record.usage / record.size
    end
  end
end

function Usage:add_method (method_name, parsed)
  local file_path = parsed.file_path;
  self.counts[method_name] = self.counts[method_name] or 0
  if not self.method_to_file_paths[method_name] then
    self.method_to_file_paths[method_name] = {file_path}
  elseif not array_contains(self.method_to_file_paths[method_name], file_path) then
    self.method_to_file_paths[method_name][#self.method_to_file_paths[method_name] + 1] = file_path
  end

  if not self.file_paths[file_path] then
    local size = string.len(parsed.source)
    self.file_paths[file_path] = {
      file_path = file_path,
      methods = {},
      methods_per_byte = self.counts[method_name] / size,
      size = size,
      usage = self.counts[method_name],
    }
  end
  self.file_paths[file_path].methods[#self.file_paths[file_path].methods + 1] = method_name
  self.file_paths[file_path].usage = self.file_paths[file_path].usage + self.counts[method_name]
  self.file_paths[file_path].methods_per_byte = self.file_paths[file_path].usage / self.file_paths[file_path].size
end

return M
