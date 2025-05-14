vim.api.nvim_create_user_command('KKMarpStart', require('kk-marp').start_presentation, { desc = 'Start presentation' })
vim.api.nvim_create_user_command('KKMarpExport', require('kk-marp').export_presentation, { desc = 'Export presentation' })
