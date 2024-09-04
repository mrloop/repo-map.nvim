-- https://aider.chat/2023/10/22/repomap.html
-- https://github.com/paul-gauthier/aider/blob/d0ebc7a810f2fbc82bc86f1fafbc90b6d0397b9b/aider/website/docs/repomap.md
-- https://github.com/paul-gauthier/aider/blob/7b2379c7c20efdf7a8d4a5e12d4a9c81162b7a70/aider/repomap.py#L29

local ts = vim.treesitter;

local M = {}

local function iterate_files_in_dir(directory, callback)
  local handle = vim.loop.fs_scandir(vim.fn.expand(directory))
  if not handle then return end

  while true do
    local name, type = vim.loop.fs_scandir_next(handle)
    if not name then break end

    local full_path = directory .. '/' .. name
    if type == 'directory' and name ~= '.git' then
      -- Recursively iterate through the subdirectory
      iterate_files_in_dir(full_path, callback)
    elseif type == 'file' then
      -- Process the file (e.g., print the file path)
      callback(full_path);
    end
  end
end

local function parse_file(filepath)
  local file = io.open(filepath, 'r')
  if not file then
    error('Could not open file: ' .. filepath)
  end
  local source = file:read('*all')
  file:close()

  local language = vim.filetype.match({ filename = filepath })
  if language then
    local ok, parser = pcall(ts.get_string_parser,source, language);
    if ok then
      local tree = parser:parse()[1]
      local node = tree:root()
      return { node = node, source = source, language = language, filepath = filepath };
    else
      print('parser error', parser)
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

-- Helper function to extract the text of a node, considering multiple lines
local function get_node_text(node, source)
  if node then
    local start_row, start_col, end_row, end_col = node:range()
    -- Single-line node
    local lines = split(source, "\n")
    return lines[start_row + 1]:sub(start_col + 1, end_col)
  end
  return nil
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

local function process_file(filepath)
  local parsed = parse_file(filepath)
  if parsed and parsed.node then
    print(print_info(parsed.node, parsed.source))
  end
end

local query_string = [[
  ;; Query to capture class definitions, method definitions, and method calls
  (class_declaration name: (identifier) @class_name)
  (method_definition name: (property_identifier) @method_name)
  (function_declaration name: (identifier) @function_name)
  (call_expression function: (identifier) @method_call)
  (call_expression function: (member_expression property: (property_identifier) @method_call))
]]

local function array_contains(arr, val)
  for i = 1, #arr do
    if arr[i] == val then
      return true
    end
  end
  return false
end

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
  local query = ts.query.parse(parsed.language, query_string);

  for id, node, _ in query:iter_captures(parsed.node, parsed.source, 0, -1) do
    local name = ts.get_node_text(node, parsed.source)
    local capture_name = query.captures[id]

    if capture_name == 'class_name' then
      usage:add_class(name, parsed.filepath)

    elseif  capture_name == "method_name" then
      local class_name = 'nil'
      local class_node = find_first_parent(node, 'class_declaration')
      if class_node then
        class_name = get_node_text(class_node:field('name')[1], parsed.source) or 'nil';
      end
      usage:add_method(class_name, class_node, name, node, parsed.filepath)

    elseif capture_name == "function_call" or capture_name == "method_call" then
      usage:count(name)
     end
   end
end

function M.repoMap(dirpath, max_tokens)
  local output = '';
  local usage = Usage:new();
  iterate_files_in_dir(dirpath, function(filepath)
    local parsed = parse_file(filepath)
    if parsed and parsed.node then
      output = output .. filepath .. ':\n' .. print_info(parsed.node, parsed.source) .. '\n'
      collect_usage(parsed, usage)
    end
  end)

-- iterate over files and count usage of methods
--    methods with the same name in different classes will be counted against each class
--    if class for method not yet record put in the __unclassified bucket
-- sort list, interate over files in list and print classes.
--
-- we need to reference count by different class name and by method name
--
-- method_to_classes[method] = {};
-- class_defs

  -- print(output)
  print(vim.inspect(usage))
  return output;
end

Usage = {}

function Usage:new()
  local o = {
    counts = {},
    -- default nil to collect yet to be seen classes / methods
    class_defs = { },
    method_to_classes = { },
  }

  setmetatable(o, self)
  self.__index = self
  return o;
end

function Usage:count (method_name)
  self.counts[method_name] = (self.counts[method_name] or 0) + 1
  local class_names = self.method_to_classes[method_name];

  --print('method_to_classes:' .. vim.inspect(self.method_to_classes));
  --print('class_names['..  method_name .. ']:' .. vim.inspect(class_names));
  --print('count: ' .. method_name)
  if class_names then
    for _, class_name in ipairs(class_names) do
      self.class_defs[class_name].usage = self.class_defs[class_name].usage + 1
    end
  end
end

function Usage:add_class (name, filepath)
  self.class_defs[name] = self.class_defs[name] or { name = name, methods = {}, usage = 0, filepath = filepath }
end

function Usage:add_method (class_name, class_node, name, node, filepath)
  self.counts[name] = self.counts[name] or 0
  if not self.method_to_classes[name] then
    self.method_to_classes[name] = {class_name}
  elseif not array_contains(self.method_to_classes[name], class_name) then
    self.method_to_classes[name][#self.method_to_classes[name] + 1] = class_name
  end

  if not self.class_defs[class_name] then
    self.class_defs[class_name] = { name = class_name, methods = {}, usage = self.counts[name], filepath = filepath }
  end
  --print('self.counts['.. name ..']:' .. self.counts[name])
  self.class_defs[class_name].methods[#self.class_defs[class_name].methods + 1] = name
  self.class_defs[class_name].usage = self.class_defs[class_name].usage + self.counts[name]
end


return M
