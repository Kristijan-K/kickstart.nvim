if not vim.fn.has 'nvim-0.5' then
  vim.api.nvim_echo({ { 'SF Execute needs Neovim >= 0.5', 'WarningMsg' } }, true, {})
  return
end

vim.api.nvim_create_user_command('SFExecute', function(opts)
  local config = vim.fn.json_decode(opts.args)
  require('sf').sf_execute(config)
end, { nargs = 1, desc = 'Execute SF command' })
