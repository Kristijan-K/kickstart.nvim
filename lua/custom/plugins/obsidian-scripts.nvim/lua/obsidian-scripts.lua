local function open_or_create_weekly_note()
  local Path = require 'obsidian.path'

  -- Get current week info
  local today = os.date '*t'
  local year = today.year
  local week = os.date '!%V' -- ISO 8601 week number (01–53)

  local filename = string.format('Week-%s-%s.md', year, week)
  local full_path = Path:new(vim.fn.expand '~/Obsidian/Weekly/' .. '/' .. filename)

  -- Check if note already exists
  if full_path:exists() then
    vim.cmd('e ' .. full_path.filename)
  else
    -- Create and open the new weekly note file
    vim.cmd('e ' .. full_path.filename)

    -- Insert template (after file loads)
    vim.defer_fn(function()
      vim.cmd 'ObsidianTemplate Weekly.md'
    end, 50)
  end
end

local function open_obsidian_today()
  vim.cmd 'ObsidianToday'
end

local function new_obsidian_document_with_template(template, location)
  local Path = require 'obsidian.path'

  vim.ui.input({ prompt = 'Enter new note title: ' }, function(title)
    if not title or title == '' then
      return
    end

    -- Slugify the filename
    local slug = title:gsub(' ', '-'):gsub('[^%w%-]', ''):lower()
    local filename = slug .. '.md'

    -- Define your desired folder (e.g., Inbox in Work vault)
    local note_path = Path:new(vim.fn.expand('~/Obsidian/' .. location .. '/' .. filename))

    -- Open the file (create if doesn't exist)
    vim.cmd('e ' .. note_path.filename)

    -- Insert the Note.md template
    vim.defer_fn(function()
      local cmd = 'ObsidianTemplate ' .. template
      vim.cmd(cmd)
    end, 50)
  end)
end

local function new_obsidian_note_with_template()
  new_obsidian_document_with_template('Note.md', '00-Inbox')
end

local function new_obsidian_presentation_with_template()
  new_obsidian_document_with_template('Presentation.md', 'Presentation')
end

-- Lua function to insert a template by filename
local function insert_obsidian_template(template_name)
  -- Define the full path to the template file
  local template_path = '~/Obsidian/Templates/' .. template_name .. '.md'
  template_path = vim.fn.expand(template_path)

  local lines = vim.fn.readfile(template_path)
  if not lines or vim.tbl_isempty(lines) then
    vim.notify("Template '" .. template_name .. "' not found or is empty.", vim.log.levels.WARN)
    return
  end

  -- Insert the template content into the current buffer
  vim.api.nvim_put(lines, 'l', true, true)
end

-- Permanently delete the current note
local function deleteCurrentNote()
  local file = vim.api.nvim_buf_get_name(0)
  if file == '' then
    vim.notify('No file loaded', vim.log.levels.WARN)
    return
  end

  local deleted_dir = vim.fn.expand '~/Obsidian/Work/Deleted/' -- Adjust path to match your structure
  vim.fn.mkdir(deleted_dir, 'p') -- Ensure the Deleted folder exists

  local filename = vim.fn.fnamemodify(file, ':t') -- Get the filename
  local target_path = deleted_dir .. '/' .. filename

  if file ~= target_path then
    vim.cmd 'write'
    vim.fn.rename(file, target_path)
    vim.cmd('e ' .. target_path)

    vim.notify('Note moved to Deleted folder: ' .. target_path, vim.log.levels.INFO)
  else
    vim.notify('Note is already in the Deleted folder', vim.log.levels.INFO)
  end
end

-- Move current note to Zettelkasten/{tag} or Zettelkasten/Archive
local function moveNoteByTag()
  local file = vim.api.nvim_buf_get_name(0)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  -- Find first [[tag]] match without slashes
  local tag
  for _, line in ipairs(lines) do
    local found = line:match '%[%[([^%[%]/]-)%]%]'
    if found then
      tag = found
      break
    end
  end

  local target_dir
  if tag then
    target_dir = vim.fn.expand('~/Obsidian/Zettelkasten/' .. tag)
  else
    target_dir = vim.fn.expand '~/Obsidian/Zettelkasten/archive'
  end

  vim.fn.mkdir(target_dir, 'p')

  local filename = vim.fn.fnamemodify(file, ':t')
  local target_path = target_dir .. '/' .. filename

  if file ~= target_path then
    vim.cmd 'write'
    vim.fn.rename(file, target_path)
    vim.cmd('e ' .. target_path)
    vim.notify('Moved note to: ' .. target_path, vim.log.levels.INFO)
  else
    vim.notify('Note already in correct location', vim.log.levels.INFO)
  end
end

local function addInboxFilesToQuickfix()
  local inbox_dir = vim.fn.expand '~/Obsidian/00-Inbox/' -- adjust if necessary
  local files = vim.fn.glob(inbox_dir .. '*.md', true, true) -- Get all .md files in Inbox folder

  if #files == 0 then
    vim.notify('No files in Inbox', vim.log.levels.INFO)
    return
  end

  -- Prepare quickfix list
  local qflist = {}
  for _, file in ipairs(files) do
    table.insert(qflist, { bufnr = vim.fn.bufadd(file), filename = file })
  end

  -- Set the quickfix list and open it
  vim.fn.setqflist({}, 'r', { items = qflist })
  vim.cmd 'copen' -- Open quickfix window
  vim.notify('Inbox files added to quickfix list', vim.log.levels.INFO)
end

-- Keymap to insert Todo.md template with Alt+t
vim.keymap.set('n', '<leader>ot', function()
  insert_obsidian_template 'Todo'
end, { desc = 'Insert Todo.md template' })
vim.keymap.set('n', '<leader>oz', addInboxFilesToQuickfix, { desc = 'Add Inbox files to quickfix' })
vim.keymap.set('n', '<leader>ox', deleteCurrentNote, { desc = 'Delete current note' })
vim.keymap.set('n', '<leader>om', moveNoteByTag, { desc = 'Move note to Zettelkasten/{tag} or Archive' })
vim.keymap.set('n', '<leader>on', new_obsidian_note_with_template, { desc = 'New note from Note.md template' })
vim.keymap.set('n', '<leader>op', new_obsidian_presentation_with_template, { desc = 'New Preentation from Presentation.md template' })
vim.keymap.set('n', '<leader>od', open_obsidian_today, { desc = "Open today's daily note" })
vim.keymap.set('n', '<leader>ow', open_or_create_weekly_note, { desc = 'Open/Create Weekly Note from Template' })
