local repo_map = require('repo-map')

vim.api.nvim_create_user_command(
  'RepoMap',
  function(opts)
    local result = repo_map.repoMap(vim.fn.getcwd())
    print(result)
  end,
  { nargs = '*' }
)
