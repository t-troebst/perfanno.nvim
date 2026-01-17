.PHONY: test format lint

test:
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

format:
	stylua lua/

lint:
	lua-language-server --check $(PWD) --checklevel=Warning
