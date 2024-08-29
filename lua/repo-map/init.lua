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

function M.repoMap(dirpath)
  local output = '';
  iterate_files_in_dir(dirpath, function(filepath)
    local parsed = parse_file(filepath)
    if parsed and parsed.node then
      output = output .. filepath .. ':\n' .. print_info(parsed.node, parsed.source) .. '\n'
    end
  end)
  print(output)
  return output;
end

return M
