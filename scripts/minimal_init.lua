-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.cmd([[let &rtp.=','.getcwd()]])

-- Set up 'mini.test' only when calling headless Neovim (like with `make test`)
if #vim.api.nvim_list_uis() == 0 then
  -- Add 'mini.nvim' to 'runtimepath' to be able to use 'mini.test'
  -- Assumed that 'mini.nvim' is stored in 'deps/mini.nvim'
  vim.cmd('set rtp+=deps/mini.nvim')
  -- Set up 'mini.test'
  require('mini.test').setup()

  -- Set up nvim-treesitter
  vim.cmd('set rtp+=deps/nvim-treesitter')
  require('nvim-treesitter.configs').setup {
    ensure_installed = { "javascript" },
    sync_install = true,
    auto_install = true,
  }
end

-- Setup logging of child proccess
local logFile = "/tmp/neovim_child_output.log"
local f = io.open(logFile, "w") -- Open log file in write mode
if f then
  f:write("Child print output:\n") -- Write message to file
  f:close();
end

-- See child print output
_G.original_print = print -- Save original print function
function print(...)
  _G.original_print(...) -- Call original print function
  local message = table.concat({...}, "\t")
  local file = io.open(logFile, "a") -- Open log file in append mode
  if file then
    file:write(message .. "\n") -- Write message to file
    file:close()
  end
end
