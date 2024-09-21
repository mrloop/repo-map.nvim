local repo_map = require('repo-map')

vim.api.nvim_create_user_command(
  'RepoMap',
  function(opts)
    local start_time = os.clock()
    local num_tokens = tonumber(opts.args)

    local result = repo_map.repoMap(vim.fn.getcwd(), num_tokens)
    local end_time = os.clock()
    print('Time taken: ' .. (end_time - start_time) .. ' seconds')
    print(result)
  end,
  { nargs = '?' }
)
