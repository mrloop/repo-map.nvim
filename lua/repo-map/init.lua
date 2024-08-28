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
      return { node = node, source = source };
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


local indent = 2;
-- Function to recursively traverse and print the desired nodes
-- http://neovim.io/doc/user/treesitter.html#treesitter-node
-- https://github.com/tree-sitter/tree-sitter
local function print_info(node, source, context, level)
  context = context or {}
  level = level or 0

  local node_type = node:type()
  local output = '';

  if node_type == 'class_declaration' then
    -- Get and print the class name
    local class_name_node = node:field('name')[1] -- Assumes 'name' is the correct field
    local class_name = get_node_text(class_name_node, source)
    context.in_class = true;
    output = output .. (string.rep(' ', level * indent) .. 'Class: ' .. class_name) .. '\n'

  elseif node_type == 'variable_declarator' and not context.in_function and not context.in_method and not context.in_variable then
    -- Get and print the class variable name
    local var_name_node = node:field('name')[1]
    local var_name = get_node_text(var_name_node, source)
    context.in_variable = true;
    output = output .. (string.rep(' ', level * indent) .. 'Variable: ' .. var_name) .. '\n'

  elseif node_type == 'function_declaration' then
    -- Get and print the function name and parameters
    local func_name_node = node:field('name')[1]
    local parameters_node = node:field('parameters')[1]
    local func_name = get_node_text(func_name_node, source)
    local parameters = get_node_text(parameters_node, source)
    context.in_function = true;
    output = output .. (string.rep(' ', level * indent) .. 'Function: ' .. func_name .. '(' .. parameters .. ')') .. '\n';

  elseif node_type == 'field_definition' then
    local field_property_node = node:field('property')[1]
    local field_property  = get_node_text(field_property_node, source)
    local field_value_node = node:field('value')[1]
    local field_value  = get_node_text(field_value_node, source)
    output = output .. (string.rep(' ', level * indent) .. 'Field: ' .. field_property .. '=' .. field_value) .. '\n'

  elseif node_type == 'method_definition' then
    local func_name_node = node:field('name')[1]
    local parameters_node = node:field('parameters')[1]
    local func_name = get_node_text(func_name_node, source)
    local parameters = get_node_text(parameters_node, source)
    context.in_method = true;
    output = output .. (string.rep(' ', level * indent) .. 'Method: ' .. func_name .. '(' .. parameters .. ')') .. '\n'

  else
    level = level - 1;
  end

  -- Recursively print child nodes
  for child in node:iter_children() do
    output = output .. print_info(child, source, context, level + 1)
  end
  return output;
end

function M.repoMap(dirpath)
  local output = '';
  iterate_files_in_dir(dirpath, function(filepath)
    local parsed = parse_file(filepath)
    if parsed and parsed.node then
      output = output .. filepath .. ':\n' .. print_info(parsed.node, parsed.source) .. '\n'
    end
  end)
  return output;
end

return M
