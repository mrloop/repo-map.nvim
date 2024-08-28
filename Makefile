# Run all test files
test: deps/mini.nvim deps/nvim-treesitter deps/todomvc
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run test from file at `$FILE` environment variable
test_file: deps/mini.nvim deps/nvim-treesitter deps/todomvc
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

# Download 'mini.nvim' to use its 'mini.test' testing module
deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none --depth=1 https://github.com/echasnovski/mini.nvim $@

deps/nvim-treesitter:
	@mkdir -p deps
	git clone --filter=blob:none --depth=1 https://github.com/nvim-treesitter/nvim-treesitter $@

deps/todomvc:
	@mkdir -p deps
	git clone --filter=blob:none --depth=1 https://github.com/tastejs/todomvc.git $@
	cd $@ && git fetch --depth=1 origin 643cab2e0d5154130077df6356e53871f3b0fa84
	cd $@ && git checkout 643cab2e0d5154130077df6356e53871f3b0fa84
