local M = {}

local is_windows = vim.loop.os_uname().version:match 'Windows'

M.start_presentation = function()
  local fullpath = vim.fn.expand '%:p'
  local dir = vim.fn.expand '%:p:h'
  local filename_no_ext = vim.fn.expand '%:t:r'
  local sep = is_windows and '\\' or '/'
  local output_file = dir .. sep .. filename_no_ext .. '.html'

  local cmd_marp = 'marp ' .. fullpath .. ' -o ' .. output_file
  local open_cmd = is_windows and ('start "" "file:///' .. output_file .. '"') or ('xdg-open "' .. output_file .. '"')

  vim.schedule(function()
    vim.notify('Running Marp command:\n' .. cmd_marp, vim.log.levels.INFO)
  end)

  vim.fn.system { 'marp', fullpath, '-o', output_file }
  vim.cmd('!' .. open_cmd)
end

M.export_presentation = function()
  local fullpath = vim.fn.expand '%:p'
  local dir = vim.fn.expand '%:p:h'
  local filename_no_ext = vim.fn.expand '%:t:r'
  local sep = is_windows and '\\' or '/'
  local output_file = dir .. sep .. filename_no_ext .. '.pdf'

  local cmd_marp = 'marp ' .. fullpath .. ' -o ' .. output_file
  local open_cmd = is_windows and ('start "" "file:///' .. output_file .. '"') or ('xdg-open "' .. output_file .. '" &')

  vim.schedule(function()
    vim.notify('Running Marp command:\n' .. cmd_marp, vim.log.levels.INFO)
  end)

  vim.fn.system { 'marp', '--pdf', fullpath, '-o', output_file, '--allow-local-files' }
  vim.cmd('!' .. open_cmd)
end

return M
